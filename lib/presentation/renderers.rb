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

      def self.read(source, &block)
        [SuperfluousFile, TiltTemplate, PassThrough].each do |renderer_type|
          return if renderer_type.read(source, &block)
        end
        raise "Don’t know how to handle item at #{source}"  # TODO: test once pipeline is customizable
      end

      class Base
        def attach_to(item)
        end
      end

      class SuperfluousFile < Base
        def self.read(source, &block)
          return unless source.ext == ".superf"

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

            renderer =
              if kind == :script  # TODO: recurse back to read instead? shouldn't be .superf special case
                RubyScript.new(section) if ext == "rb"
              elsif kind == :style  # temporary shim for test site; TODO: implement CSS bundling as plugin
                PassThrough.new(section.content)
              else
                TiltTemplate.read_template(section)
              end

            unless renderer
              raise "Unsupported #{kind} type #{ext.inspect} at #{section}"
            end

            yield(
              logical_path: section.relative_path.sub_ext(""),
              piece: Piece.new(kind:, source: section, renderer:))
          end
          return :success
        end

      private

        FENCE_BAR = / *[-–]{3,}\s*/
        NEXT_FENCE = /^ (?=#{FENCE_BAR}) | \z /x
        FENCE = /^ #{FENCE_BAR} (?<kind>\w+)\.(?<ext>\w+?) #{FENCE_BAR} $/x
      end

      # Handles template files: Haml, Erb, Sass, etc.
      #
      class TiltTemplate < Base
        def self.read(source, &block)
          return unless renderer = read_template(source)
          yield(
            logical_path: source.relative_path.sub_ext(""),
            piece: Piece.new(kind: :template, source:, renderer:)
          )
          return :success
        end

        def self.read_template(source)
          # TODO: fix possible symlink issue on next line (should context be source or target dir?)
          Dir.chdir(source.full_path.parent) do  # for relative includes (e.g. sass) embedded in template
            return nil unless template_class = Tilt.template_for(source.ext)
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

      # Handler for unprocessed file exts
      #
      class PassThrough < Base
        def self.read(source, &block)
          yield(
            logical_path: source.relative_path,  # Don't strip ext for raw files
            piece: Piece.new(kind: :template, source:, renderer: self.new(source.content))
          )
          return :success
        end

        def initialize(content)
          @content = content
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

class StringScanner
  def line_number
    string.byteslice(0, pos).count("\n") + 1  # inefficient, but… ¯\_(ツ)_/¯
  end
end
