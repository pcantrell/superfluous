require 'ostruct'
require 'json'
require 'yaml'
require 'kramdown'
require 'front_matter_parser'

module Superfluous
  module Data
    class Dict < OpenStruct
      attr_accessor :id, :index

      def each(&block)
        each_pair { |key, value| yield value }
      end
    end

    # Recursively read and merge the entire contents of `dir` into a unified data tree.
    #
    def self.read(dir, logger:)
      raise "#{dir.to_s} is not a directory" unless dir.directory?

      data = Dict.new

      file_count = 0
      dir.each_child do |child|
        logger.log child, temporary: !logger.verbose

        child_key = child.basename.to_s
        next if child_key =~ /^\./  # Never parse dotfiles

        if child.directory?
          new_data, sub_file_count = read(child, logger:)
          file_count += sub_file_count
        else
          child_key.sub!(/\.[^\.]+$/, "")  # key = filename without extension
          new_data = wrap(parse_file(child))
          file_count += 1
        end

        if child_key == "_self"  # file contents apply to dir itself
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

    # Make `new_data` a child of `data`, recursively merging it with any existing data at `key`.
    #
    def self.merge_child(data, key, new_data)
      unless existing_data = data[key]
        data[key] = new_data  # TODO: handle existing nil value? or not?
        if new_data.is_a?(Dict)
          new_data.id ||= key.to_sym
        end
        return
      end

      return if key == :id && existing_data == new_data

      unless existing_data.is_a?(Dict) && new_data.is_a?(Dict)
        raise "Cannot merge data for #{key}:" +
          "\n  value 1: #{existing_data.inspect} " +
          "\n  value 2: #{new_data.inspect}"
      end

      merge(existing_data, new_data)
    end

    # Recursively merge two data trees, modifying `existing_data` in place.
    #
    def self.merge(existing_data, new_data)
      new_data.each_pair do |child_key, child_value|
        merge_child(existing_data, child_key, child_value)
      end
    end

    # Recursively wrap hashes as Superfluous Dicts, looking inside arrays and leaving other objects
    # untouched. Sets id and index properties as appropriate.
    #
    def self.wrap(data, id: nil, index: nil)
      case data
        when Hash
          result = Dict.new
          result.id = id.to_sym if id
          result.index = index if index
          data.each do |key, value|
            result[key] = wrap(value, id: key)
          end
          result
        when Array
          data.map.with_index { |elem, index| wrap(elem, index:) }.freeze
        else
          data.freeze if data.respond_to?(:freeze)
          data
      end
    end
  end
end
