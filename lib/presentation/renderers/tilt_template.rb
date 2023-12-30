module Superfluous
  module Presentation
    module Renderer

      # Handles template files: Haml, Erb, Sass, etc.
      #
      class TiltTemplate < Base
        def self.try_infer_pieces(source, &block)
          try_read_single_piece(
            source:,
            kind: :template,  # If Tilt supports the file format, infer that it’s a template
            logical_path: source.relative_path.sub_ext(""),
            &block
          )
        end

        def self.renderer_for(kind:, source:)
          return unless kind == :template
          return unless template_class = Tilt.template_for(source.ext)

          # TODO: fix possible symlink issue on next line (should context be source or target dir?)
          Dir.chdir(source.full_path.parent) do  # for relative includes (e.g. sass) embedded in template
            self.new(
              template_class.new(source.full_path, source.line_num) do
                source.content
              end
            )
          end
        end

        def initialize(tilt_template)
          @tilt_template = tilt_template
        end

        def render(context)
          yield(context.with(
            props: context.props.merge(
              content: render_to_string(context))))
        end

        def render_to_string(context)
          @tilt_template.render(context.scope, context.props) do
            if context.nested_content.nil?
              raise "Template called yield, but no nested content given"
            end
            context.nested_content.call.html_safe
          end
        end
      end

    end
  end
end
