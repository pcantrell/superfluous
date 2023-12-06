require 'tilt'
require 'active_support/all'
require 'tmpdir'
require_relative 'asset_handlers'

def process_site(site_dir:, data:, output_dir:)
  Pathname.glob("**/*", base: site_dir) do |relative_path|
    context = ItemContext.new(site_dir:, item_path: relative_path, data: data)
    next if context.skip?
    
    log context.relative_path, newline: false
    out_prefix = nil

    process_item(context) do |props:, content:, strip_ext:|
      output_file_relative = context.output_path(props:, strip_ext:)
      
      if out_prefix
        log out_prefix, newline: false
      else
        out_prefix = " " * context.relative_path.to_s.size
      end
      log " → #{output_file_relative}"

      output_file = output_dir + output_file_relative
      # TODO: verify that output_file is within output_dir
      output_file.parent.mkpath
      File.write(output_file, content)
    end
  end
end

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
  handler = AssetHandler.for(context.full_path)

  content = eval_setup(handler.setup, context, props) do |scope:, props:|
    props.freeze
    yield(
      content: handler.render(scope:, props:, nested_content:),
      props: props,
      strip_ext: handler.strip_ext?
    )
  end
rescue => e
  log "ERROR while processing #{context.full_path}"
  raise
end

class ItemContext
  def initialize(site_dir:, item_path:, data:)
    @site_dir = site_dir
    @relative_path = Pathname.new(
      item_path.cleanpath.to_s
        .delete_prefix(site_dir.cleanpath.to_s)
        .delete_prefix("/")
    )
    @data = data
  end

  attr_reader :site_dir, :relative_path, :data

  FILENAME_PROP = /\[(.*)\]/

  def file_name
    @file_name ||= relative_path.basename.to_s
  end

  def full_path
    @full_path ||= site_dir + relative_path
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
      props[$1.to_sym]
    end
  end

  def for_relative(path)
    self.class.new(site_dir:, item_path: path, data:)
  end
end

# Methods availabe to site scripts and templates
class RenderingScope
  def initialize(context)
    @context = context
  end
end

module TemplateHelpers
  # Render a partial. Overrides render during template processing.
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
        process_item(partial_context, props:, nested_content: nested_content) do |content:, props:, strip_ext:|
          result = content.html_safe
        end
        return result
      end
    end
    raise "No template found for partial #{partial}"
      + " (Searching for _#{partial}.* in #{@context.search_paths.join(', ')})"
  end
end

def eval_setup(setup_code, context, props, &block)
  # Create scope for prop usage and helps defs in setup code
  setup_scope_class = Class.new(RenderingScope) do
    def make_setup_script_binding
      binding
    end
  end
  setup_scope = setup_scope_class.new(context)

  template_scope = Class.new(setup_scope_class) do
    include TemplateHelpers
  end.new(context)

  if setup_code.nil?
    # No setup code; props go to template unmodified
    yield(scope: template_scope, props: props)
  else
    # Setup code present

    # Create binding where evaled code will execute in our new scope.
    setup_scope_binding = setup_scope.make_setup_script_binding
    props.each do |k,v|
      setup_scope_binding.local_variable_set(k, v)
    end

    render_count = 0
    setup_scope_class.define_method(:render) do |**props_from_setup|
      render_count += 1
      if context.singleton? && render_count > 1
        raise "Singleton item setup attempted to call render() multiple times: #{@context.full_path}"
      end
      yield(scope: template_scope, props: props.merge(props_from_setup))
    end
    setup_scope_binding.eval(setup_code)

    if context.singleton? && render_count != 1
      raise "Singleton item setup must call render() exactly once: #{@context.full_path}"
    end
  end
end
