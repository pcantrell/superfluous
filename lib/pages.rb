require 'tilt'
require_relative 'asset_handlers'

PROP_IN_FILENAME = /\[(.*)\]/

def process_pages(pages_dir:, data:, output_dir:)
  Pathname.glob("**/*", base: pages_dir) do |relative_path|
    full_path = pages_dir + relative_path
    next if full_path.directory?
    
    puts relative_path

    process_page(full_path, data) do |props:, content:, strip_ext:|
      out_path = relative_path
      out_path = out_path.sub_ext("") if strip_ext
      out_path = out_path.parent + out_path.basename.to_s.gsub(PROP_IN_FILENAME) do
        props[$1.to_sym]
      end
      outfile = output_dir + out_path
      # TODO: verify that outfile is within output_dir
      outfile.parent.mkpath
      File.write(outfile, content)
    end
  end
end

def process_page(path, data)
  original_path = path
  props = {}
  
  handler = AssetHandler.for(path)
  path_has_props = path.basename.to_s !~ PROP_IN_FILENAME

  content = eval_setup(handler.setup, data, singleton_page: path_has_props) do |props|
    props.freeze
    yield(
      content: handler.render(props),
      props: props,
      strip_ext: handler.strip_ext?
    )
  end
rescue => e
  puts "ERROR while processing #{path}"
  raise
end

def eval_setup(setup_code, data, singleton_page:, &block)
  result = binding.eval(setup_code) do |props|
    raise "cannot yield from singleton page template" if singleton_page
    yield({ data: data }.merge(props))
  end

  if singleton_page
    result = if result.respond_to?(:to_h)
      result.to_h
    else
      {}
    end
    yield({ data: data }.merge(result))
  end
end
