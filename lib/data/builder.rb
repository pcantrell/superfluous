require_relative 'tree_node'
require 'ostruct'
require 'json'
require 'yaml'
require 'kramdown'

module Superfluous
  module Data

    # Recursively read and merge the entire contents of `dir` into a unified data tree.
    #
    def self.read(dir = nil, context:, ignore:, top_level: true)
      dir ||= context.data_dir
      raise "#{dir.to_s} is not a directory" unless dir.directory?

      data = Dict.new
      file_count = 0
      dir.each_child do |child|
        context.logger.log child, temporary: !context.logger.verbose

        next if ignore.call(child)
        next if child.basename.to_s.start_with?(/\.|_[^\.]/)  # skip dotfiles, _foo

        child_keys = child.basename.to_s.split('.')

        if child.directory?
          new_data, sub_file_count = read(child, context:, ignore:, top_level: false)
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

      data = apply_script_transform(dir, data, ignore:)
      data.superf_name = "data" if top_level && data.respond_to?(:superf_name=)

      [data, file_count]
    end

  private

    def self.parse_file(file)
      case file.extname
        when ".json"
          [JSON.parse(file.read), :strip_extension]
        when ".yaml"
          [YAML.load(file.read), :strip_extension]
        when ".md"
           match = file.read.match %r{
            \A\s*
            (
              ^[-–]{3,}\s*
              (?<yaml> .*?)
              ^[-–]{3,}\s*
            )?
            (?<markdown> .*)\Z
          }mx
          raise "Unable to extract markdown" unless match

          data = YAML.load(match[:yaml] || '{}').merge(
            content: Kramdown::Document.new(match[:markdown]).to_html)

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

    def self.apply_script_transform(dir, data, ignore:)
      Superfluous::read_dir_scripts(dir, ignore:, parent_class: DataScriptBase).new
        .transform(data)  # TODO: But might scripts want to inherit from parents? That breaks this!
    end

    module DataWrapping
      # Recursively wrap eligible types (hashes and arrays) as Superfluous TreeNodes, leaving other
      # objects untouched. Sets id, index, and parent properties as appropriate.
      #
      def wrap(data, id: nil, index: nil, parent: nil)
        case data
          when TreeNode
            data
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

    extend DataWrapping

    class DataScriptBase
      def transform(data)
        data
      end

      include DataWrapping
    end
  end
end
