module Superfluous
  module Presentation
    module Renderer

      class SuperfluousFile
        def self.try_infer_pieces(source, &block)
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

            Renderer.read_single_piece(source: section, kind:, logical_path:, &block)
          end
          return :success
        end

        def self.try_read_single_piece(kind:, source:, logical_path:, &block)
          # A .superf file can only be a container for pieces, not a whole piece unto itself
          :unrecognized
        end

      private

        FENCE_BAR = / *[-–]{3,}\s*/
        NEXT_FENCE = /^ (?=#{FENCE_BAR}) | \z /x
        FENCE = /^ #{FENCE_BAR} #{KIND_AND_EXT_PATTERN} #{FENCE_BAR} $/x
      end

    end
  end
end
