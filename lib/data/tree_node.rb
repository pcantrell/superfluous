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

      def attach!(parent:, id: nil, index: nil)
        @parent = parent
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
          return @table[match[:key].to_sym] = args[0]

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
