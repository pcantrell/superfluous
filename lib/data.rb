require 'ostruct'
require 'json'
require 'yaml'
require 'kramdown'
require 'front_matter_parser'

module Superfluous
  module Data

    module DataElement
      attr_accessor :id, :index
      attr_accessor :superf_name, :superf_parent  # for internal use in error messages

      def attach!(parent:, id:, index:)
        self.superf_parent = parent
        self.id = id&.to_sym
        self.index = index
      end

      def superf_data_path
        path = superf_name || ""
        path << superf_parent.superf_data_path if superf_parent
        path << ".#{id}" if id
        path << "[#{index}]" if index
        path
      end
    end

    class Dict
      include DataElement

      def initialize
        @table = {}
      end

      def each_pair(&block)
        @table.each_pair(&block)
      end

      def each(&block)
        each_pair { |key, value| yield value }
      end

      def keys
        @table.keys
      end

      def has_key?(key)
        return @table.has_key?(key.to_sym)
      end

      def values
        @table.values
      end

      def [](*keys)
        return @table[keys[0].to_sym] if keys.size == 1

        val = self
        keys.each do |key|
          val = val[key]
          return nil if val.nil?
        end
        return val
      end

      def to_h
        @table
      end

      def []=(key, value)
        @table[key.to_sym] = value
      end

      def method_missing(method, *args, **kwargs)
        if match = method.to_s.match(/^(?<key>.*)\=$/)
          return @table[match[:key].to_sym] = args[0]
        elsif match = method.to_s.match(/^(?<key>.*)\?$/)
          unless args.empty? && kwargs.empty?
            raise "Expected 0 args, got #{args.size} args + #{kwargs.size} keywords"
          end
          return @table[match[:key].to_sym]
        elsif @table.has_key?(method)
          unless args.empty? && kwargs.empty?
            raise "Expected 0 args, got #{args.size} args + #{kwargs.size} keywords"
          end
          @table[method]
        else
          raise NoMethodError, "No key `#{method}` at #{superf_data_path}; available keys: #{keys}"
        end
      end
    end

    class Array < ::Array
      include DataElement
    end

    # Recursively read and merge the entire contents of `dir` into a unified data tree.
    #
    def self.read(dir, top_level: true, logger:)
      raise "#{dir.to_s} is not a directory" unless dir.directory?

      data = Dict.new
      data.superf_name = "data" if top_level

      file_count = 0
      dir.each_child do |child|
        logger.log child, temporary: !logger.verbose

        child_key = child.basename.to_s
        next if child_key =~ /^\./  # Never parse dotfiles

        if child.directory?
          new_data, sub_file_count = read(child, top_level: false, logger:)
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
          new_data.superf_parent = data
          new_data.id = key.to_sym
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
    def self.wrap(data, id: nil, index: nil, parent: nil)
      case data
        when Hash
          result = Dict.new
          result.attach!(parent:, id:, index:)
          result.index = index if index
          data.each do |key, value|
            result[key] = wrap(value, id: key, parent: result)
          end
          result
        when ::Array
          result = Array.new
          result.concat(
            data.map.with_index do |elem, index|
              wrap(elem, index:, parent: result)
            end
          )
          result.attach!(parent:, id:, index:)
          result
        else
          data
      end
    end
  end
end
