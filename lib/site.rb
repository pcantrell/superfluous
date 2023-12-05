require 'tilt'
require 'active_support/all'
require_relative 'asset_handlers'

def process_site(site_dir:, data:, output_dir:)
  output_dir.rmtree
  output_dir.mkdir

  Pathname.glob("**/*", base: site_dir) do |relative_path|
    context = ItemContext.new(site_dir:, item_path: relative_path, data: data)
    next if context.skip?
    
    log context.relative_path

    process_item(context) do |props:, content:, strip_ext:|
      output_file = output_dir + context.output_path(props:, strip_ext:)
      # TODO: verify that output_file is within output_dir
      output_file.parent.mkpath
      File.write(output_file, content)
    end
  end
end

def process_item(context, props: {})
  props = { data: context.data }.merge(props)
  handler = AssetHandler.for(context.full_path)

  content = eval_setup(handler.setup, context, props) do |scope:, props:|
    props.freeze
    yield(
      content: handler.render(scope:, props:),
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

  # Render a partial
  def render(partial, **props, &block)
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
        # How to pass block to render??
        process_item(partial_context, props:) do |content:, props:, strip_ext:|
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
  scope_class = Class.new(RenderingScope) do
    def make_setup_script_binding
      binding
    end
  end
  scope = scope_class.new(context)

  # Create binding where evaled code will execute in our new scope.
  scope_binding = scope.make_setup_script_binding do |props_from_setup|
    # Confusingly, this block here does not execute immediately; it is the block that `yield`s in
    # the setup code will call.
    raise "cannot yield from singleton item template" if context.singleton?
    yield(scope:, props: props.merge(props_from_setup))
  end
  props.each do |k,v|
    scope_binding.local_variable_set(k, v)
  end

  result = scope_binding.eval(setup_code)

  if context.singleton?
    props_from_setup = if Hash === result
      result
    else
      {}
    end
    yield(scope:, props: props.merge(props_from_setup))
  end
end
