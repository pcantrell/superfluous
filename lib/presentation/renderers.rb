require 'strscan'
require_relative 'item'

module Superfluous
  module Presentation
    module Renderer
      Context = ::Data.define(:props, :scope, :nested_content, :partial_renderer) do
        def override_props(**overrides)
          with(props: props.merge(overrides))
        end
      end

      KIND_AND_EXT = /(?<kind> \w+ ) (?<ext> \. \w+)/x

      # Yields one or more pieces from the given source. If the source’s path has a `+kind.ext`
      # suffix, this method returns a single piece of that explicitly expressed kind (exactly as in
      # a .superf file). Otherwise, this method infers what kind(s) of piece(s) the source contains.
      #
      def self.each_piece(source, &block)
        if match = source.relative_path.to_s.match(/^(?<prefix> .* ) \+ #{KIND_AND_EXT} $/x)
          read_piece(
            source:,
            kind: match[:kind].to_sym,
            logical_path: Pathname.new(match[:prefix]),
            &block
          )
        else
          infer_pieces(source, &block)
        end
      end

      def self.read_piece(kind:, source:, logical_path:, &block)
        renderer = case kind
          when :script
            RubyScript.new(source) if source.ext == ".rb"
          when :style  # temporary shim for test site; TODO: implement CSS bundling as plugin
            StyleAttachment.new(source)
          when :template
            TiltTemplate.renderer_for(source)
          else
            PassThrough.new(source)  # ignore unknown type; Item.add_piece will flag it
        end
        unless renderer
          raise "Unsupported #{kind} type #{source.ext.inspect} at #{source}"
        end
        yield(logical_path:, piece: Piece.new(kind:, source:, renderer:))
      end

      # Attempts to infer the kind of the source from its file ext. Yields once for each recognized
      # piece within the source (because .superf files may contain multiple pieces). Treats sources
      # with no other matching handler as static assets by returning a template piece with a
      # pass-through renderer.
      #
      def self.infer_pieces(source, &block)
        [SuperfluousFile, TiltTemplate, PassThrough].each do |renderer_type|
          case result = renderer_type.infer_pieces(source, &block)
            when :success      then return
            when :unrecognized then next
            else raise "Incorrect return value from #{renderer_type}.infer_pieces: #{result.inspect}"
          end
        end
        raise "Don’t know how to handle item at #{source}"  # TODO: test once pipeline is customizable
      end

      class Base
        def attach_to(item)
        end
      end

      class SuperfluousFile < Base
        def self.infer_pieces(source, &block)
          return :unrecognized unless source.ext == ".superf"
          logical_path = source.relative_path.sub_ext("")

          scanner = StringScanner.new(source.content)
          
          before_first = scanner.scan_until(NEXT_FENCE)
          unless before_first.blank?
            raise "Illegal content before first –––fence––– at #{source}:\n  #{before_first.inspect}"
          end

          until scanner.eos?
            scanner.scan(FENCE) or raise "Malformed fence at #{source.full_path}:#{scanner.line_number}"
            kind = scanner[:kind].to_sym
            ext = scanner[:ext]
            section = source.subsection(
              ext:,
              line_num: scanner.line_number,
              content: scanner.scan_until(NEXT_FENCE)
            )

            Renderer.read_piece(source: section, kind:, logical_path:, &block)
          end
          return :success
        end

      private

        FENCE_BAR = / *[-–]{3,}\s*/
        NEXT_FENCE = /^ (?=#{FENCE_BAR}) | \z /x
        FENCE = /^ #{FENCE_BAR} #{KIND_AND_EXT} #{FENCE_BAR} $/x
      end

      # Handles template files: Haml, Erb, Sass, etc.
      #
      class TiltTemplate < Base
        def self.infer_pieces(source, &block)
          return :unrecognized unless renderer = renderer_for(source)
          yield(
            logical_path: source.relative_path.sub_ext(""),
            piece: Piece.new(kind: :template, source:, renderer:)
          )
          return :success
        end

        def self.renderer_for(source)
          # TODO: fix possible symlink issue on next line (should context be source or target dir?)
          Dir.chdir(source.full_path.parent) do  # for relative includes (e.g. sass) embedded in template
            return unless template_class = Tilt.template_for(source.ext)
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
          context.props[:content] = @tilt_template.render(context.scope, context.props) do
            if context.nested_content.nil?
              raise "Template called yield, but no nested content given"
            end
            context.nested_content.call.html_safe
          end
          yield(context)
        end
      end

      # Static assets copied through without modification
      #
      class PassThrough < Base
        def self.infer_pieces(source, &block)
          yield(
            logical_path: source.relative_path,  # Don't strip ext for raw files
            piece: Piece.new(kind: :template, source:, renderer: self.new(source))
          )
          return :success
        end

        def initialize(source)
          @content = source.content
        end

        def render(context)
          # TODO: support returning path for fast / symlinked asset copy
          yield(context.override_props(content: @content))
        end
      end

      class RubyScript < Base
        def initialize(source)
          @source = source
        end

        def attach_to(item)
          item.scope_class.class_eval(@source.content, @source.full_path.to_s, @source.line_num)

          unless item.scope_class.instance_methods.include?(:build)
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

      class StyleAttachment < Base
        def initialize(source)
        end

        def render(context)
          yield(context)
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
        def initialize(context:, next_pipeline_step:)
          @context = context
          @next_pipeline_step = next_pipeline_step
        end

        def partial(partial, **props, &block)
          @context.partial_renderer.call(partial, **props, &block)
        end

        def render(**props_from_script)
          @next_pipeline_step.call(
            @context.override_props(**props_from_script)
          )
        end
      end
    end
  end
end
