require 'tilt'
require 'active_support/all'
require 'tmpdir'
require_relative 'asset_handlers'

module Superfluous
  # One build pass of the site. Retains template and script caches, so create a new instance to pick
  # up changes to input files.
  #
  class SiteBuild
    def initialize(logger:)
      @logger = logger

      @asset_handler_cache = AssetHandler::Cache.new
    end

    # Traverses and processes the site directory, replacing existing files in the output dir but
    # leaving any extraneous / straggler files untouched.
    #
    def process_site(site_dir:, data:, output_dir:)
      Pathname.glob("**/*", base: site_dir) do |relative_path|
        context = ItemContext.new(build: self, site_dir:, item_path: relative_path, data:)
        next if context.skip?
        
        log_file_processing(context) do |log_output_file:|
          process_item(context) do |props:, content:, strip_ext:|  # Block receives processed content
            output_file_relative = context.output_path(props:, strip_ext:)
            log_output_file.call(output_file_relative)

            output_file = output_dir + output_file_relative
            # TODO: verify that output_file is within output_dir
            output_file.parent.mkpath
            File.write(output_file, content)
          end
        end
      end
    end

  private

    def log_file_processing(context)
      @logger.log context.relative_path, newline: false
      subsequent_line_prefix = nil
      output_count = 0

      yield(
        log_output_file: Proc.new do |output_file_relative|
          if output_count == 0 || @logger.verbose
            if subsequent_line_prefix
              @logger.log subsequent_line_prefix, newline: false
            else
              subsequent_line_prefix = " " * context.relative_path.to_s.size
            end
          end
          @logger.log " → #{output_file_relative}", temporary: !@logger.verbose
          output_count += 1
        end
      )

      if !@logger.verbose
        @logger.make_last_temporary_permanent
        if output_count > 1
          @logger.log "#{subsequent_line_prefix} → …#{output_count - 1} more…"
        end
      end
    end

  public

    # Renders a new version of the site to a tmp dir, then quickly swaps out the out contents of the
    # output dir with the completed results.
    #
    def process_site_clean(output_dir:, **kwargs)
      Dir.mktmpdir do |work_dir|
        work_dir = Pathname.new(work_dir)

        process_site(output_dir: work_dir, **kwargs)

        Dir.mktmpdir do |old_output|
          FileUtils.mv output_dir.children, old_output
          FileUtils.mv work_dir.children, output_dir
        end
      end
    end

    def process_item(context, props: {}, nested_content: nil)
      props = { data: context.data }.merge(props)
      handler = @asset_handler_cache.for(context.full_path)
      return unless handler

      content = eval_script(handler.script, context, props) do |scope:, props:|
        props.freeze
        yield(
          content: handler.render(scope:, props:, nested_content:),
          props:,
          strip_ext: handler.strip_ext?
        )
      end
    rescue Exception => e
      raise ::Superfluous::BuildFailure.wrap(e,
        context_path: context.site_dir.realpath, item_path: context.relative_path)
    end

    # Where did a given site item come from? What kind of item is it?
    #
    class ItemContext
      def initialize(build:, site_dir:, item_path:, data:)
        @build = build
        @site_dir = site_dir.realpath
        @relative_path = Pathname.new(
          item_path.cleanpath.to_s
            .delete_prefix(site_dir.cleanpath.to_s)
            .delete_prefix("/")
        )
        @data = data
      end

      attr_reader :build, :site_dir, :relative_path, :data

      FILENAME_PROP = /\[(.*)\]/

      def file_name
        @file_name ||= relative_path.basename.to_s
      end

      def full_path
        @full_path ||= (site_dir + relative_path).realpath
      end

      def search_paths
        @search_paths ||= begin
          result = relative_path.parent.ascend.map do |ancestor|
            site_dir + ancestor
          end
          result << site_dir unless result[-1] == site_dir
          result
        end
      end

      def skip?
        full_path.directory? || file_name.start_with?("_")
      end

      def singleton?
        file_name !~ FILENAME_PROP
      end

      def output_path(props:, strip_ext:)
        path = relative_path
        path = path.sub_ext("") if strip_ext
        path.parent + path.basename.to_s.gsub(FILENAME_PROP) do
          value = props[$1.to_sym]
          if value.nil?
            raise "Prop [#{$1}] appears in filename #{path}, but no value given;" +
              " available props are: #{props.keys.join(', ')}"
          end
          value
        end
      end

      def for_relative(path)
        self.class.new(build:, site_dir:, item_path: path, data:)
      end
    end

    # Methods shared by site scripts and templates. Each script gets its own subclass of
    # RenderingScope, which includes:
    #
    # - the scripts’s `render` method to trigger template rendering, and
    # - any `def`s from the script.
    #
    class RenderingScope
      def initialize(context)
        @context = context
      end

      def inspect
        "<<rendering scope `#{@context.relative_path}`>>"
      end
    end

    # Methods available only to the template and not the script.
    #
    module TemplateHelpers
      # Note that `render` has a different meaning in templates vs scripts. The is the method
      # for tempaltes, which overrides the `render` that scripts see.
      #
      def render(partial, **props, &nested_content)
        @context.search_paths.each do |search_path|
          found_path = nil
          search_path.glob("_#{partial}.*") do |path|
            raise "Conflicting templates:\n  #{path}\n  #{found_path}" if found_path
            found_path = path
          end
          if found_path
            partial_context = @context.for_relative(found_path)
            unless partial_context.singleton?
              raise "Included partials cannot have [params] in filenames: #{found_path}"
            end

            result = nil
            @context.build.process_item(
              partial_context,
              props:,
              nested_content:
            ) do |content:, props:, strip_ext:|
              result = content.html_safe
            end
            return result  # Don't keep searching parent dirs; partial found!
          end
        end
        raise "No template found for partial #{partial}"
          + " (Searching for _#{partial}.* in #{@context.search_paths.join(', ')})"
      end
    end

    def eval_script(script, context, props, &block)
      # Create scope for prop usage and helps defs in script code
      # TODO: Create a scope class per script instead of per script eval?
      script_scope_class = Class.new(RenderingScope) do
        def make_script_script_binding
          binding
        end
      end
      script_scope = script_scope_class.new(context)

      template_scope = Class.new(script_scope_class) do
        include TemplateHelpers
      end.new(context)

      if script.nil?
        # No script code; props go to template unmodified
        yield(scope: template_scope, props:)
      else
        # Setup code present

        # Create binding where evaled code will execute in our new scope.
        script_scope_binding = script_scope.make_script_script_binding
        props.each do |k,v|
          script_scope_binding.local_variable_set(k, v)
        end

        render_count = 0
        script_scope_class.define_method(:render) do |**props_from_script|
          render_count += 1
          if context.singleton? && render_count > 1
            raise "Singleton item script attempted to call render() multiple times: #{@context.full_path}"
          end
          yield(scope: template_scope, props: props.merge(props_from_script))
        end
        script_scope_binding.eval(script)

        if context.singleton? && render_count != 1
          raise "Singleton item script must call render() exactly once: #{context.full_path}"
        end
      end
    end
  end
end
