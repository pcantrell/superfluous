require 'ostruct'
require 'json'
require 'yaml'
require 'kramdown'
require 'front_matter_parser'

module Superfluous
  module Data
    def self.read(dir, logger:)
      raise "Data directory #{dir.to_s} is not a directory" unless dir.directory?

      data = OpenStruct.new

      file_count = 0
      dir.each_child do |child|
        logger.log child, temporary: !logger.verbose

        child_key = child.basename.to_s
        next if child_key =~ /^\./

        if child.directory?
          new_data, sub_file_count = read(child, logger:)
          file_count += sub_file_count
        else
          child_key.sub!(/\.[^\.]+$/, "")
          new_data = wrap(parse_file(child))
          file_count += 1
        end

        if child_key == "_"
          merge(data, new_data)
        else
          merge_child(data, child_key, new_data)
        end
      end

      [data, file_count]
    end

    def self.parse_file(file)
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

    def self.merge_child(data, key, new_data)
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

    def self.merge(existing_data, new_data)
      new_data.each_pair do |child_key, child_value|
        merge_child(existing_data, child_key, child_value)
      end
    end

    def self.wrap(data)
      case data
        when Hash
          result = OpenStruct.new
          data.each do |key, value|
            result[key] = wrap(value)
          end
          result
        when Array
          data.map { |elem| wrap(elem) }
        else
          data.freeze if data.respond_to?(:freeze)
          data
      end
    end
  end
end
