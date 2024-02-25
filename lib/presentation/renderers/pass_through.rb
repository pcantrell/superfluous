module Superfluous
  module Presentation
    module Renderer

      # Static assets copied through without modification
      #
      class PassThrough < Base
        def self.try_infer_pieces(source, &block)
          # Anything can be a static asset. Treat as a template; don’t strip ext for logical path.
          try_read_single_piece(kind: :template, source:, logical_path: source.relative_path, &block)
        end

        def self.renderer_for(kind:, source:)
          self.new(source) if kind == :template
        end

        def initialize(source)
          @content = source.content_or_path
        end

        def render(context)
          yield(context.override_props(content: @content))
        end
      end

    end
  end
end
