module Superfluous
  module Presentation
    module Renderer

      class RubyScript < Base
        def self.renderer_for(kind:, source:)
          self.new(source) if kind == :script && source.ext == ".rb"
        end

        def initialize(source)
          @source = source
        end

        def prepare(context)
          context.item.scope_class.class_eval(@source.content, @source.full_path.to_s, @source.line_num)

          unless context.item.scope_class.instance_methods.include?(:build)
            raise "Script does not define a `build` method: #{@source}"
          end
        end

        def render(context)
          build_args = {}
          context.scope.method(:build).parameters.each do |kind, name|
            if (kind == :key || kind == :keyreq) && context.props.has_key?(name)
              build_args[name] = context.props[name]
            end
          end

          context.scope.build(**build_args)
        end
      end

    end
  end
end
