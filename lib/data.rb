require 'ostruct'
require 'json'
require 'yaml'
require 'kramdown'
require 'front_matter_parser'

def read_data(dir)
  raise "Data directory #{dir.to_s} is not a directory" unless dir.directory?

  data = OpenStruct.new

  dir.each_child do |child|
    log child
    child_key = child.basename.to_s
    next if child_key =~ /^\./

    if child.directory?
      new_data = read_data(child)
    else
      child_key.sub!(/\.[^\.]+$/, "")
      new_data = wrap_data(parse_file(child))
    end

    if child_key == "_"
      merge(data, new_data)
    else
      merge_child(data, child_key, new_data)
    end
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

def merge_child(data, key, new_data)
  unless existing_data = data[key]
    data[key] = new_data  # TODO: handle existing nil value? or not?
    return
  end

  unless existing_data.is_a?(OpenStruct) && new_data.is_a?(OpenStruct)
    raise "Cannot merge data for #{key}:" +
      " existing data is #{existing_data.class} " +
      " but new data is #{new_data.class}"
  end

  merge(existing_data, new_data)
end

def merge(existing_data, new_data)
  new_data.each_pair do |child_key, child_value|
    merge_child(existing_data, child_key, child_value)
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
