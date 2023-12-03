require 'tilt'

PROP_IN_FILENAME = /\[(.*)\]/

def process_pages(pages_dir:, data:, output_dir:)
  Pathname.glob("**/*", base: pages_dir) do |relative_path|
    full_path = pages_dir + relative_path
    next if full_path.directory?
    
    puts relative_path

    process_page(full_path, data) do |rendered, props|
      out_path = relative_path.sub_ext("")
      out_path = out_path.parent + out_path.basename.to_s.gsub(PROP_IN_FILENAME) { props[$1.to_sym] }
      outfile = output_dir + out_path
      # TODO: verify that outfile is within output_dir
      outfile.parent.mkpath
      File.write(outfile, rendered)
    end
  end
end

def process_page(path, data)
  original_path = path
  props = {}
  setup, content = parse_setup(path)
  
  # TODO: Allow chained templates, e.g. `.css.scss.erb`?
  template_class = Tilt.template_for(path) || PassThroughTemplate
  template = template_class.new(path) { content }

  content = eval_setup(
    setup,
    data,
    singleton_page: path.basename.to_s !~ PROP_IN_FILENAME
  ) do |props|
    props.freeze
    yield(template.render(Object.new, props), props)
  end
rescue => e
  puts "ERROR while processing #{path}"
  raise
end

def parse_setup(path)
  setup_from_file = read_setup_file(path)
  embedded_setup, content = extract_embedded_setup(path)

  if setup_from_file && embedded_setup
    # TODO: support nested setups?
    raise "#{path} cannot have both embedded setup and setup from a file"
  end

  [
    setup_from_file || embedded_setup || "",
    content
  ]
end

def read_setup_file(path)
  # TODO: support dir-level shared setup?
  stripped_path = path
  while stripped_path.extname != ""
    stripped_path = stripped_path.sub_ext("")
  end
  setup_file = stripped_path.sub_ext("-setup.rb")
  setup_file.read if setup_file.exist?
end

def extract_embedded_setup(path)
  raw_content = path.read
  if raw_content =~ /\A\s*--- *\n(.*?)^ *--- *\n(.*)\Z/m
    [$1, $2]
  else
    [nil, raw_content]
  end
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

class PassThroughTemplate
  def initialize(path)
    @content = yield
  end

  def render(props)
    @content
  end
end
