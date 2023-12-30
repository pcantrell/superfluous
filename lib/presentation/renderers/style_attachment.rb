module Superfluous
  module Presentation
    module Renderer

      # Shim impl for now
      class StyleAttachment < Base
        def self.renderer_for(kind:, source:)
          self.new(source) if kind == :style
        end

        def initialize(source)
          @source = source
        end

        def prepare(item:, build_context:)
          # stub for now
        end

        def render(context)
          yield(context)
        end
      end

    end
  end
end
