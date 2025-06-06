module Superfluous
  module Data
    module Wrapping
      # Recursively wrap eligible types (hashes and arrays) as Superfluous TreeNodes, leaving other
      # objects untouched. Sets id, index, and parent properties as appropriate.
      #
      def wrap(data, id: nil, index: nil, parent: nil, override_existing: false)
        case data
          when TreeNode
            data
          when Hash
            result = Dict.new
            result.attach!(parent:, id:, index:, override_existing:)
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
            result.attach!(parent:, id:, index:, override_existing:)
            result
          else
            data
        end
      end
    end

    module TreeNode
      extend Wrapping

      %i[id index parent].each do |attr|
        define_method(attr) do |*args|
          @table[attr] || instance_variable_get("@#{attr}")
        end

        define_method("#{attr}=") do |*args|
          raise "#{self.class}##{attr} is read-only; use `attach!` to reparent a node"
        end
      end

      attr_accessor :superf_name  # for internal use in error messages

      def attach!(parent:, id: nil, index: nil, override_existing: false)
        @parent = parent
        unless override_existing
          id = @id || id
          index = @index || index
        end
        @id = id&.to_sym if id
        @index = index if index
      end

      def superf_data_path
        path = superf_name || ""
        path << @parent.superf_data_path if @parent
        path << ".#{@id}" if @id
        path << "[#{@index}]" if @index
        path
      end
    end

    class Array < ::Array
      include TreeNode

      def to_s
        "[#{join(", ")}]"
      end
    end

    class Dict
      include TreeNode

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
        if keys.size == 1
          key = keys[0]
          if key.is_a?(Hash)
            required_key = key[:required]
            result = self[required_key]
            if result.nil?
              raise "Missing required key #{required_key.inspect} at #{superf_data_path}"
            end
            return result
          elsif key.respond_to?(:to_sym)
            return @table[key.to_sym]
          else
            raise "malformed lookup key: #{key}"
          end
        end

        val = self
        keys.each do |key|
          val = val[key]
          return nil if val.nil?
        end
        return val
      end

      def []=(key, value)
        @table[key.to_sym] = TreeNode.wrap(value, id: key, parent: self)
      end

      def to_h
        @table
      end

      def to_s(value_method: :to_s)
        "Dict{#{keys.join(", ")}}"
      end

      def inspect
        top = Thread.current[:superf_inspect].nil?
        Thread.current[:superf_inspect] ||= Set.new
        return "{...#{superf_data_path}...}" if Thread.current[:superf_inspect].include?(self)

        begin
          Thread.current[:superf_inspect].add(self)
          "Dict@" + superf_data_path + @table.inspect
        ensure
          Thread.current[:superf_inspect] = nil if top
        end
      end

      def method_missing(method, *args, **kwargs)
        if match = method.to_s.match(/^(?<key>.*)\=$/)  # .foo =
          return self[match[:key].to_sym] = args[0]

        elsif match = method.to_s.match(/^(?<key>.*)\?$/)  # .foo?
          unless args.empty? && kwargs.empty?
            raise "#{method}: Expected 0 args, got #{args.size} args + #{kwargs.size} keywords"
          end
          return @table[match[:key].to_sym]

        elsif @table.has_key?(method)  # .foo
          unless args.empty? && kwargs.empty?
            raise "#{method}: Expected 0 args, got #{args.size} args + #{kwargs.size} keywords"
          end
          @table[method]

        else
          raise NoMethodError, "No Dict key `#{method}` for #{superf_data_path};"+
            " available keys are: #{keys}"
        end
      end
    end

  end
end
