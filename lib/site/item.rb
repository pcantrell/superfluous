module Superfluous
  module Site
    # A source of site presentation content, either a whole file or a part of one
    #
    class Source
      def initialize(site_dir:, relative_path:, ext: nil, line_num: 1, content: nil)
        @site_dir = site_dir
        @relative_path = relative_path
        @line_num = line_num
        @content = content
        @ext = ext || relative_path.extname
        @full_path = (site_dir + relative_path).realpath
      end

      attr_reader :full_path, :site_dir, :relative_path, :line_num, :ext

      def content
        @content || full_path.read
      end

      def subsection(ext:, line_num:, content:)
        self.class.new(site_dir:, relative_path:, ext:, line_num:, content:)
      end

      def to_s
        "#{full_path}:#{line_num}"
      end
    end

    # One logical unit of several parts from the site/ directory, which may span multiple files.
    #
    class Item
      def initialize(logical_path, scope_class)
        @logical_path = logical_path
        @scope_class = scope_class
        @pieces_by_kind = {}
      end

      attr_reader :logical_path, :scope_class

      def add_piece(piece)
        raise "Unknown kind of piece: #{piece.kind}" unless PROCESSING_ORDER.include?(piece.kind)
          
        if existing_piece = @pieces_by_kind[piece.kind]
          raise "Conflicting `#{piece.kind}` pieces_by_kind for #{logical_path}:" +
            [piece, existing_piece].map { |p| "\n  in #{piece.location}" }.join
        end

        @pieces_by_kind[piece.kind] = piece

        piece.renderer.attach_to(self)
      end

      PROCESSING_ORDER = [:script, :template, :style]

      def pieces
        PROCESSING_ORDER.map { |kind| @pieces_by_kind[kind] }.compact
      end

      def partial?
        logical_path.basename.to_s =~ PARTIAL_PATTERN
      end

      def singleton?
        @logical_path.basename.to_s !~ PROP_PATTERN
      end

      def partial_search_paths
        @partial_search_paths ||= Array(logical_path.ascend.drop(1)) + [Pathname.new('.')]
      end

      def output_path(props:)
        logical_path.parent + logical_path.basename.to_s.gsub(PROP_PATTERN) do
          key = $1.to_sym
          unless props.has_key?(key)
            raise "Prop [#{$1}] appears in #{logical_path}, but no value given;" +
              " available props are: #{props.keys.join(', ')}"
          end
          props[key]
        end
      end

    private

      PARTIAL_PATTERN = /^_/
      PROP_PATTERN = /\[(.*)\]/
    end

    Piece = ::Data.define(:kind, :source, :renderer)
  end
end
