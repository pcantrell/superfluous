require_relative 'tree_node'
require 'ostruct'
require 'json'
require 'yaml'
require 'kramdown'
require 'front_matter_parser'

module Superfluous
  module Data

    # Recursively read and merge the entire contents of `dir` into a unified data tree.
    #
    def self.read(dir, top_level: true, logger:)
      raise "#{dir.to_s} is not a directory" unless dir.directory?

      data = Dict.new
      data.superf_name = "data" if top_level

      file_count = 0
      dir.each_child do |child|
        logger.log child, temporary: !logger.verbose

        child_keys = child.basename.to_s.split('.')
        next if child_keys.first.empty?  # Filename started with `.`; never parse dotfiles

        if child.directory?
          new_data, sub_file_count = read(child, top_level: false, logger:)
          file_count += sub_file_count
        else
          new_data, ext_action = parse_file(child)
          child_keys.pop if ext_action == :strip_extension
          file_count += 1
        end

        # Turn dot chain in filename into tree traversal
        new_data = wrap(
          child_keys.reverse.reduce(new_data) do |data, key|
            if key == "_"
              data
            else
              { key.to_sym => data }
            end
          end
        )

        merge(data, new_data)
      end

      [data, file_count]
    end

    def self.parse_file(file)
      case file.extname
        when ".json"
          [JSON.parse(file.read), :strip_extension]
        when ".yaml"
          [YAML.load(file.read), :strip_extension]
        when ".md"
          parts = FrontMatterParser::Parser.parse_file(file)
          data = parts.front_matter.merge(
            content: Kramdown::Document.new(parts.content).to_html)
          [data, :strip_extension]
        else
          [file, :keep_extension]
      end
    end

    # Make `new_data` a child of `data`, recursively merging it with any existing data at `key`.
    #
    def self.merge_child(data, key, new_data)
      unless existing_data = data[key]
        data[key] = new_data  # TODO: handle existing nil value? or not?
        if new_data.is_a?(TreeNode)
          new_data.attach!(parent: data, id: key, index: nil)
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

    # Recursively wrap eligible types (hashes and arrays) as Superfluous TreeNodes, leaving other
    # objects untouched. Sets id, index, and parent properties as appropriate.
    #
    def self.wrap(data, id: nil, index: nil, parent: nil)
      case data
        when Hash
          result = Dict.new
          result.attach!(parent:, id:, index:)
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
