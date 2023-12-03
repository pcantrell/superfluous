require 'ostruct'

require 'json'
require 'yaml'
require 'kramdown'
require 'front_matter_parser'

def read_data(dir)
  raise "Data directory #{dir.to_s} is not a directory" unless dir.directory?

  data = {}

  dir.each_child do |child|
    child_name = child.basename.to_s
    next if child_name =~ /^\./

    # TODO: conflicting keys, merge or error?
    if child.directory?
      data[child_name] = read_data(child)
    else
      data[child.basename.sub_ext("").to_s] = parse_file(child)
    end
  end

  wrap_data(data)
end

def wrap_data(data)
  case data
    when Hash
      result = OpenStruct.new
      data.each do |key, value|
        result[key] = wrap_data(value)
      end
      result
    when Array
      data.map { |e| wrap_data(e) }
    else
      data
  end
end

def parse_file(file)
  case file.extname
    when ".json"
      JSON.parse(file.read)
    when ".yaml"
      YAML.load(file.read)
    when ".md"
      parts = FrontMatterParser::Parser.parse_file(file)
      {
        meta: parts.front_matter,
        content: Kramdown::Document.new(parts.content).to_html
      }
    else
      raise "Unknown data file extension #{file.extname} for #{file.to_s}"
  end
end

