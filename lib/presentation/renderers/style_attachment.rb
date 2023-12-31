module Superfluous
  module Presentation
    module Renderer

      class StyleAttachment < Base
        def self.renderer_for(kind:, source:)
          self.new(source) if kind == :style
        end

        def initialize(source)
          @source = source
        end

        def prepare(context)
          config = { isolation: :none }
          if context.item.scope_class.respond_to?(:style_config)
            config.merge!(context.item.scope_class.style_config)
          end

          isolation = config[:isolation].to_sym
          output_path = (context.item.logical_relative(config[:output]) if config[:output])
          unless output_path
            raise "#{context.item} must specify an output path for its style section"
          end

          # TODO: make data available here? scope?
          # TODO: raise helpful errors for unknown ext
          # TODO: warn if not CSS
          css = "\n\n/* #{context.item.logical_path} */\n\n"
          css += TiltTemplate.renderer_for(kind: :template, source: @source)
            .render_to_string(
              Renderer::RenderingContext.new(props: {}, scope: nil, nested_content: nil))

          # Clear output file now, but give template item a chance to populate it before
          # attempting to append our own CSS
          context.builder.output(output_path, "", existing: :overwrite)

          context.builder.after_build do
            context.builder.output(output_path, css, existing: :append)
          end
        end

        def render(context)
          yield(context)
        end
      end

    end
  end
end
