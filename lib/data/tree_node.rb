module Superfluous
  module Data

    module TreeNode
      attr_reader :id, :index, :parent
      %w[id index parent].each do |attr|
        define_method("#{attr}=") do |*args|
          raise "#{self.class}##{attr} is read-only; use `attach!` to reparent a node"
        end
      end

      attr_accessor :superf_name  # for internal use in error messages

      def attach!(parent:, id:, index:)
        @parent = parent
        @id = id&.to_sym
        @index = index
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
        return @table[keys[0].to_sym] if keys.size == 1

        val = self
        keys.each do |key|
          val = val[key]
          return nil if val.nil?
        end
        return val
      end

      def []=(key, value)
        @table[key.to_sym] = value
      end

      def to_h
        @table
      end

      def to_s(value_method: :to_s)
        "{ " + @table.map { |k,v| "#{k}: #{v.send(value_method)}" }.join(", ") + " }"
      end

      def inspect
        "Dict@" + superf_data_path + to_s(value_method: :inspect)
      end

      def method_missing(method, *args, **kwargs)
        if match = method.to_s.match(/^(?<key>.*)\=$/)
          return @table[match[:key].to_sym] = args[0]
        elsif match = method.to_s.match(/^(?<key>.*)\?$/)
          unless args.empty? && kwargs.empty?
            raise "#{method}: Expected 0 args, got #{args.size} args + #{kwargs.size} keywords"
          end
          return @table[match[:key].to_sym]
        elsif @table.has_key?(method)
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