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

        ISOLATION_MODES = %i[none css_nesting shadow_dom].freeze

        def prepare(context)
          config = { isolation: :none }
          if context.item.scope_class.respond_to?(:style_config)
            config.merge!(context.item.scope_class.style_config)
          end

          isolation_mode = config[:isolation].to_sym
          unless ISOLATION_MODES.include?(isolation_mode)
            raise "Unknown isolation mode #{isolation_mode.inspect};" +
              " must be one of: #{ISOLATION_MODES.inspect}"
          end

          output_path = (context.item.logical_relative(config[:output]) if config[:output])
          unless output_path
            raise "#{context.item} must specify an output path for its style section"
          end

          self_id = context.builder.concise_id(self.class, :style, context.item.logical_path)

          css = render_css_template(@source, context)

          if :css_nesting == isolation_mode
            @css_wrapper_class = self_id
            css = render_css_template(
              @source.subsection(
                ext: ".scss",  # Use scss to distribute wrapper class to all selectors
                content: ".#{@css_wrapper_class} { #{css} }"),
              context
            )
          end

          css = "\n\n/* #{context.item.logical_path} */\n\n" + css

          # Clear output file now, but give template item a chance to populate it before
          # attempting to append our own CSS
          context.builder.output(output_path, "", existing: :overwrite)

          context.builder.after_build do
            context.builder.output(output_path, css, existing: :append)
          end
        end

        def render(context)
          if @css_wrapper_class
            context = context.override_props(
              content: "<span class=\"#{@css_wrapper_class}\">" +
                context.props[:content] +
                "</span>"
            )
          end
          yield(context)
        end

        def render_css_template(source, context)
          # TODO: make scope available here (for helper methods)?
          # TODO: raise helpful errors for unknown ext, warn if output is not CSS
          TiltTemplate
            .renderer_for(kind: :template, source:)
            .render_to_string(
              Renderer::RenderingContext.new(
                props: { data: context.data },
                scope: nil,
                nested_content: nil))
        end
      end

    end
  end
end
