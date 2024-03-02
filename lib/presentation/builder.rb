require 'tilt'
require 'active_support/all'
require 'tmpdir'
require_relative 'renderer'
require_relative '../extensions'

module Superfluous
  module Presentation

    # Retains compiled scripts and templates, so create a new instance to pick up changes.
    #
    class Builder
      def initialize(context:)
        unless context.presentation_dir.directory?
          raise "#{context.presentation_dir.to_s} is not a directory"
        end
        @project_context = context

        @concise_ids = {}

        @items_by_logical_path = {}  # logical path → Item
        @items_by_id = {}            # id symbol → Item
        read_items(root_dir: context.presentation_dir, scope_parent_class: Renderer::RenderingScope)
      end

      # Renders a new version of the output to a tmp dir, then quickly swaps out the out entire
      # contents of the actual output dir with the completed results.
      #
      def build_clean(output_dir:, **kwargs)
        Dir.mktmpdir do |tmp_dir|
          tmp_dir = Pathname.new(tmp_dir)

          build(output_dir: tmp_dir, **kwargs)

          Dir.mktmpdir do |old_output|
            FileUtils.mv output_dir.children, old_output
            FileUtils.mv tmp_dir.children, output_dir
          end
        end

        return self
      end

    private

      def logger
        @project_context.logger
      end

      # Traverses and processes the presentation/ directory, raising an error if files exist in the
      # output dir and leaving any extraneous / straggler files untouched.
      #
      def build(data:, output_dir:)
        raise "Attempted to build twice with same Builder" if @used
        @used = true

        @output_dir = output_dir.realpath

        @after_build_actions = []

        @items_by_logical_path.values.each do |item|
          prepare_item(item, data:)
        end

        @items_by_logical_path.values.each do |item|
          next if item.partial?

          log_item_processing(item) do |log_output_file:|
            build_item(item, data:) do |context|
              output_file_relative = item.output_path(props: context.props)
              log_output_file.call(output_file_relative)

              output(output_file_relative, context.props.content)
            end
          end
        end

        @after_build_actions.each do |action|
          action.call
        end

        return self
      end

    public  # Methods available for renderers

      def after_build(&action)
        @after_build_actions << action
      end

      def output(relative_path, content, existing: :error)
        unless %i[append error].include?(existing)
          raise "Illegal value for `existing` param: #{existing.inspect}"
        end

        output_file = (@output_dir + relative_path).cleanpath
        unless @output_dir.contains?(output_file)
          raise "Item produced a dynamic output path that lands outsite the output folder" +
            "\n  relative output path: #{relative_path}" +
            "\n           resolved to: #{output_file}" +
            "\n   which is outside of: #{@output_dir}"
        end
        output_file.parent.mkpath

        if existing == :error && output_file.exist?
          raise "#{output_file} already exists"
        end

        if content.is_a?(Pathname)
          if existing == :append
            content = content.read
          else
            File.symlink(content.realpath, output_file)  # TODO: allow config to disable this
            return
          end
        end

        if output_file.symlink? && existing == :append
          tmpfile = Tempfile.create(output_file.to_s)
          FileUtils.cp(output_file, tmpfile)
          FileUtils.rm(output_file)
          FileUtils.mv(tmpfile, output_file)
        end

        File.write(output_file, content, mode: "a")
      end

      def concise_id(*key)
        @concise_ids[key] ||=
          "sf" + SecureRandom.base64(6)
            .gsub("+", "-")
            .gsub("/", "_")
            .gsub("=", "")
      end

    private

      def read_items(root_dir:, relative_subdir: Pathname(""), scope_parent_class:)
        scope_parent_class = Superfluous::read_dir_scripts(
          root_dir + relative_subdir, context: @project_context, parent_class: scope_parent_class)

        (root_dir + relative_subdir).each_child(false) do |child|
          # Ignore dir script; we read it above
          next if Superfluous::is_dir_script?(child)

          child_path = relative_subdir + child
          full_path = root_dir + child_path
          next if @project_context.ignored?(full_path)

          if full_path.directory?
            read_items(root_dir:, relative_subdir: child_path, scope_parent_class:)
          else
            source = Source.new(root_dir:, relative_path: child_path, whole_file: true)
            Renderer.each_piece(source) do |logical_path:, piece:|
              item = @items_by_logical_path[logical_path] ||=
                Item.new(logical_path, Class.new(scope_parent_class))
              item.add_piece(piece)
            end
          end
        end
      end

      def prepare_item(item, data:)
        item.prepare!(Renderer::PreparationContext.new(item:, data:, builder: self))
        
        if id = item.scope_class.id&.to_sym
          if existing_item = @items_by_id[id]
            raise "Item id #{id.inspect} is claimed by multiple items:" +
              "\n  #{existing_item}" +
              "\n  #{item}"
          end
          @items_by_id[id] = item
        end
      end

      def build_item(item, data:, props: {}, nested_content: nil, &final_step)
        check_output_count(item) do |count_output|
          partial_renderer = lambda do |partial, **props, &block|
            render_partial(partial, from_item: item, data:, **props, &block)
          end

          final_step_with_count = lambda do |*args|
            count_output.call
            final_step.call(*args)
          end
          pipeline = item.pieces.reverse.reduce(final_step_with_count) do |next_step, piece|
            lambda do |context|  # context here will come from previous steps
              renderer = lambda do |**props_from_script|
                next_step.call(
                  context.override_props(**props_from_script))
              end

              new_context = context.with(
                scope: item.scope_class.new(renderer:, partial_renderer:, item_url_resolver:))
              piece.renderer.render(new_context, &next_step)
            end
          end

          pipeline.call(
            Renderer::RenderingContext.new(
              props: Renderer::Props.new(item).merge(data:).merge(props),
              scope: nil,  # each pipeline step will get its own scope object
              nested_content:
            )
          )
        end
      end

      def check_output_count(item, &build)
        output_count = 0

        yield(Proc.new do
          output_count += 1
          if item.singleton? && output_count > 1
            raise "Singleton #{item} attempted to render multiple times"
          end
        end)

        if item.singleton? && output_count != 1
          raise "Singleton #{item} rendered #{output_count} times, but should have rendered" +
            " exactly once. The most common cause for this is a script never calling `render`."
        end
      end

      # Messy logic for a simple purpose: show a nicely formatted build tree, with multi-output
      # files collapsed when not in verbose mode.
      #
      def log_item_processing(item)
        logger.log item.logical_path, newline: false
        subsequent_line_prefix = nil
        output_count = 0

        yield(
          log_output_file: lambda do |output_file_relative|
            if output_count == 0 || logger.verbose
              if subsequent_line_prefix
                logger.log subsequent_line_prefix, newline: false
              else
                subsequent_line_prefix = " " * item.logical_path.to_s.size
              end
            end
            logger.log " → #{output_file_relative}", temporary: !logger.verbose
            output_count += 1
          end
        )

        logger.log "  ⚠️  no output", temporary: !logger.verbose if output_count == 0
        if !logger.verbose
          logger.make_last_temporary_permanent
          if output_count > 1
            logger.log "#{subsequent_line_prefix} → …#{output_count - 1} more…"
          end
        end
      end

      def find_item_by_id(id)
        unless item = @items_by_id[id.to_sym]
          raise "No item has the ID #{id.inspect}\nAvailable item IDs: #{@items_by_id.keys}"
        end
        return item
      end

      def item_url_resolver
        lambda do |id, **props|
          id ||= props.keys.first
          item = find_item_by_id(id)
          path = "/" + item.output_path(props:).to_s
          @project_context.index_filenames.each do |index|
            path.sub! %r{/#{index}$}, "/"
          end
          @project_context.auto_extensions.each do |ext|
            path.sub! %r{\.#{ext}$}, ""
          end
          path
        end
      end

      def render_partial(partial, from_item:, data:, **props, &nested_content)
        partial_item = case partial
          when String then find_partial_by_path(partial, from_item:)
          when Symbol then find_item_by_id(partial)
          else raise "Partials must be identified either by path (string) or by id (symbol);" +
            " cannot use #{partial.class} as a partial identifier: #{partial.inspect}"
        end

        unless partial_item.singleton?
          raise "Partial #{partial_item} cannot have {curly braces} in its filename"
        end

        result = nil
        build_item(partial_item, data:, props:, nested_content:) do |context|
          result = context.props
        end
        return result
      end

      def find_partial_by_path(partial, from_item:)
        partial_path = partial.to_s
        from_item.partial_search_paths.each do |search_path|
          if partial_item = @items_by_logical_path[search_path + partial_path]
            return partial_item
          end
        end
        searched_paths = from_item.partial_search_paths.map { |path| path + "#{partial_path}.*" }
        raise "No template found for partial #{partial} (Searched for #{searched_paths.join(', ')})"
      end
    end

  end
end
