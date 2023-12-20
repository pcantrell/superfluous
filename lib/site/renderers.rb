require 'strscan'
require_relative 'item'
require_relative 'ruby_script'

module Superfluous
  module Site
    module Renderer
      Context = ::Data.define(:scope, :props, :nested_content, :render_partial) do
        def override_props(**overrides)
          with(props: props.merge(overrides))
        end
      end

      def self.read(source, &block)
        [SuperfluousFile, TiltTemplate, PassThrough].each do |handler|
          return if handler.read(source, &block)
        end
        raise "Don’t know how to handle site content at #{source}"
      end

      class SuperfluousFile
        def self.read(source, &block)
          return unless source.ext == ".superf"

          scanner = StringScanner.new(source.content)
          
          before_first = scanner.scan_until(NEXT_FENCE)
          unless before_first.blank?
            raise "Illegal content before first –––fence––– in #{source}:\n  #{before_first.inspect}"
          end

          until scanner.eos?
            scanner.scan(FENCE) or raise "Malformed fence at #{scanner.charpos}"
            kind = scanner[:kind].to_sym
            ext = scanner[:ext]
            section = source.subsection(
              ext:,
              line_offset: 10000,  # TODO: set line number
              content: scanner.scan_until(NEXT_FENCE)
            )

            renderer =
              if kind == :script  # TODO: recurse back to read instead? shouldn't be .superf special case
                raise "Unsupported script type #{ext.inspect}" unless ext == "rb"
                RubyScript.new(section)
              elsif kind == :style  # temporary shim for test site; TODO: implement CSS bundling as plugin
                PassThrough.new(section.content)
              else
                TiltTemplate.read_template(section)
              end

            yield(
              logical_path: section.relative_path.sub_ext(""),
              piece: Piece.new(kind:, source: section, renderer:))
          end
          return :success
        end

      private

        FENCE_BAR = /\s*[-–]{3,}\s*/
        NEXT_FENCE = /^ (?=#{FENCE_BAR}) | \z /x
        FENCE = /^ #{FENCE_BAR} (?<kind>.+)\.(?<ext>.+?) #{FENCE_BAR} $/x
      end

      # Handles template files: Haml, Erb, Sass, etc.
      #
      class TiltTemplate
        def self.read(source, &block)
          return unless Tilt.template_for(source.full_path)
          yield(
            logical_path: source.relative_path.sub_ext(""),
            piece: Piece.new(kind: :template, source:, renderer: read_template(source))
          )
          return :success
        end

        def self.read_template(source)
          # TODO: fix possible symlink issue on next line (should context be source or target dir?)
          Dir.chdir(source.full_path.parent) do  # for relative includes (e.g. sass) embedded in template
            self.new(Tilt.new(source.ext) { source.content })
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
      class PassThrough
        def self.read(source, &block)
          yield(
            logical_path: source.relative_path,  # Don't strip ext for raw files
            piece: Piece.new(kind: :template, source:, renderer: self.new(source.content))
          )
        end

        def initialize(content)
          @content = content
        end

        def render(context)
          # TODO: support returning path for fast / symlinked asset copy
          yield(context.override_props(content: @content))
        end
      end
    end
  end
end
