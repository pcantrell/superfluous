require 'strscan'
require_relative 'item'

module Superfluous
  module Presentation

    module Renderer
      PreparationContext = ::Data.define(:item, :data, :builder)

      RenderingContext = ::Data.define(:props, :scope, :nested_content) do
        def override_props(**overrides)
          with(props: props.merge(overrides))
        end
      end

      class Props < Hash
        def initialize(item)
          @item = item
        end

        def content
          unless has_key?(:content)
            raise "Pipeline did not produce a `content` prop for #{@item}. When an item has" +
              " only a script and no template, the script must call `render(content: ...)`."
          end
          self[:content]
        end

        # Returns the content as an HTML-safe string. Often used implicitly when a template includes
        # another item as a partial.
        #
        def to_s
          content = self.content
          content = content.read if content.is_a?(Pathname)  # TODO: add test
          content.html_safe
        end
      end

      # Yields one or more pieces from the given source. If the source’s path has a `+kind.ext`
      # suffix, this method returns a single piece of that explicitly expressed kind (exactly as in
      # a .superf file). Otherwise, this method infers what kind(s) of piece(s) the source contains.
      #
      def self.each_piece(source, &block)
        if match = source.relative_path.to_s.match(/^(?<prefix> .* ) \+ #{KIND_AND_EXT_PATTERN} $/x)
          read_single_piece(
            kind: match[:kind].to_sym,
            source:,
            logical_path: Pathname.new(match[:prefix]),
            &block
          )
        else
          infer_pieces(source, &block)
        end
      end

      # Interprets the source as a piece of the given kind. Either yields exactly once (an item can
      # only have one piece of a given kind, so yielding multiple times would always cause an error
      # downstream), or raises an exception.
      #
      def self.read_single_piece(kind:, source:, logical_path:, &block)
        Item.verify_kind!(kind)

        RENDERER_TYPES.each do |renderer_type|
          result = renderer_type.try_read_single_piece(kind:, source:, logical_path:, &block)
          return if result == :success
        end
        raise "Unsupported #{kind} extension #{source.ext.inspect} at #{source}"
      end

      # Attempts to infer the kind of the source from its file ext. Yields once for each recognized
      # piece within the source (because .superf files may contain multiple pieces). Treats sources
      # with no other matching handler as static assets by returning a template piece with a
      # pass-through renderer.
      #
      def self.infer_pieces(source, &block)
        RENDERER_TYPES.each do |renderer_type|
          case result = renderer_type.try_infer_pieces(source, &block)
            when :success      then return
            when :unrecognized then next
            else raise "Incorrect return value from #{renderer_type}.infer_pieces: #{result.inspect}"
          end
        end
        # Currently unreachable because PassThrough will always infer that everything is a template
        # TODO: test once pipeline is customizable
        raise "Don’t know how to handle item at #{source}"
      end

      class Base
        # Attempts to use this renderer to interpret the given source as a piece of the given kind.
        # Either yields one piece and returns :success, or return :unrecognized (does not raise).
        #
        # This default implementation delegates to a renderer_for method in the subclass.
        #
        def self.try_read_single_piece(kind:, source:, logical_path:, &block)
          return :unrecognized unless renderer = renderer_for(kind:, source:)
          yield(logical_path:, piece: Piece.new(kind:, source:, renderer:))
          return :success
        end

        # Subclasses can override to extract pieces from an arbitrary file (e.g. to treat any `.erb`
        # file as an ERB template).
        #
        # By default, renderers never infer that they can handle a given file by extension alone;
        # they will only consider an explicitly specified kind: either in a kind.ext section of of a
        # .superf file, or in a file whose name ends with +kind.ext.
        #
        def self.try_infer_pieces(source, &block)
          return :unrecognized
        end

        # Runs exactly once per project build for each item that is rendered, before the first
        # render but after the item pipeline is fully configured. May not run for unused partials.
        #
        # Does nothing by default. Subclasses may override.
        #
        def prepare(context)
        end
      end

      # Methods used by presentation scripts and templates live in a dynamically generated subclass
      # of this class. That covers:
      #
      # - the scripts’s `render` method to trigger template rendering,
      # - the `partial` method to render a partial item, and
      # - any custom methods defined by the script.
      #
      class RenderingScope
        def initialize(renderer:, partial_renderer:, item_url_resolver:)
          @renderer = renderer
          @partial_renderer = partial_renderer
          @item_url_resolver = item_url_resolver
        end

        def build
          render
        end

        def partial(partial, **props, &block)
          @partial_renderer.call(partial, **props, &block)
        end

        def render(**props_from_script)
          @renderer.call(**props_from_script)
        end

        def url(id = nil, **props)
          @item_url_resolver.call(id, **props)
        end

        def self.id
          nil
        end
      end

    protected

      KIND_AND_EXT_PATTERN = /(?<kind> \w+ ) (?<ext> \. \w+)/x
    end

  end
end

require_relative 'renderers/superfluous_file'
require_relative 'renderers/ruby_script'
require_relative 'renderers/tilt_template'
require_relative 'renderers/pass_through'
require_relative 'renderers/style_attachment'

module Superfluous::Presentation::Renderer
  # TODO: configurable per project?
  RENDERER_TYPES = [SuperfluousFile, RubyScript, TiltTemplate, StyleAttachment, PassThrough]
end
