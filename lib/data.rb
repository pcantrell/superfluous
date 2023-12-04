require 'ostruct'

require 'json'
require 'yaml'
require 'kramdown'
require 'front_matter_parser'

def read_data(dir)
  raise "Data directory #{dir.to_s} is not a directory" unless dir.directory?

  data = OpenStruct.new

  dir.each_child do |child|
    child_name = child.basename.to_s
    next if child_name =~ /^\./

    if child.directory?
      new_data = read_data(child)
    else
      child_name.sub!(/\.[^\.]+$/, "")
      new_data = wrap_data(parse_file(child))
    end

    merge(data, child_name, new_data)
  end

  data
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
      file
  end
end

def merge(data, key, new_data)
  unless existing_data = data[key]
    data[key] = new_data  # TODO: handle existing nil value? or not?
    return
  end

  unless existing_data.is_a?(OpenStruct) && new_data.is_a?(OpenStruct)
    raise "Cannot merge data for #{key}:" +
      " existing data is #{existing_data.class} " +
      " but new data is #{new_data.class}"
  end

  new_data.each_pair do |child_key, child_value|
    merge(existing_data, child_key, child_value)
  end
end

def wrap_data(data)
  case data
    when Hash
      result = OpenStruct.new
      data.each do |key, value|
        result[key] = wrap_data(value)
      end
      result
    else
      data.freeze if data.respond_to?(:freeze)
      data
  end
end
