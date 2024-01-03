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

        ISOLATION_MODES = %i[none css_nesting].freeze

        def prepare(ctx)
          config = { isolation: :none }
          if ctx.item.scope_class.respond_to?(:style_config)
            config.merge!(ctx.item.scope_class.style_config)
          end

          isolation_mode = config[:isolation].to_sym
          unless ISOLATION_MODES.include?(isolation_mode)
            raise "Unknown isolation mode #{isolation_mode.inspect};" +
              " must be one of: #{ISOLATION_MODES.inspect}"
          end

          output_path = (ctx.item.logical_relative(config[:output]) if config[:output])
          unless output_path
            raise "#{ctx.item} must specify an output path for its style section"
          end

          self_id = ctx.builder.concise_id(self.class, :style, ctx.item.logical_path)

          css = render_css_template(@source, ctx)

          if :css_nesting == isolation_mode
            @content_wrapper = ["<span class=\"#{self_id}\">", "</span>"]
            css = render_css_template(
              @source.subsection(
                ext: ".scss",  # Use scss to distribute wrapper class to all selectors
                content: ".#{self_id} { #{css} }"),
              ctx
            )
          end

          css = "\n\n/* #{ctx.item.logical_path} */\n\n" + css

          ctx.builder.after_build do
            ctx.builder.output(output_path, css, existing: :append)
          end
        end

        FULL_HTML_DOC = %r{
          (?<preamble> \A\s* <(!DOCTYPE|html) .*? <body.*?>)
          (?<body_content> .* )
          (?<postscript> </body\s*>.*\Z)
        }mix

        def render(ctx)
          if @content_wrapper
            content = ctx.props[:content]

            if match = content.match(FULL_HTML_DOC)
              body_content = match[:body_content]
              preamble = match[:preamble]
              postscript = match[:postscript]
            else
              body_content = content
              preamble = postscript = nil
            end

            ctx = ctx.override_props(
              content: [
                preamble,
                @content_wrapper[0],
                body_content,
                @content_wrapper[1],
                postscript,
              ].join
            )
          end
          yield(ctx)
        end

        def render_css_template(source, ctx)
          # TODO: make scope available here (for helper methods)?
          # TODO: raise helpful errors for unknown ext, warn if output is not CSS
          TiltTemplate
            .renderer_for(kind: :template, source:)
            .render_to_string(
              Renderer::RenderingContext.new(
                props: { data: ctx.data },
                scope: nil,
                nested_content: nil))
        end
      end

    end
  end
end
