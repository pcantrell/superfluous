module Superfluous
  module Presentation

    # A source of presentation content, either a whole file or a part of one
    #
    class Source
      def initialize(root_dir:, relative_path:, ext: nil, line_num: 1, whole_file:, content: nil, renderer_opts:)
        @root_dir = root_dir
        @relative_path = relative_path
        @line_num = line_num
        @whole_file = whole_file
        @content = content
        @ext = ext || relative_path.extname
        @full_path = (root_dir + relative_path).realpath
        @renderer_opts = renderer_opts
      end

      attr_reader :full_path, :root_dir, :relative_path, :line_num, :ext, :renderer_opts
      attr_reader :id  # for references from other items

      def content
        @content || full_path.read
      end

      def content_or_path
        if @whole_file
          full_path
        else
          content
        end
      end

      def subsection(ext:, line_num: nil, content: nil)
        line_num ||= self.line_num
        self.class.new(ext:, line_num:, content:, whole_file: false, root_dir:, relative_path:, renderer_opts:)
      end

      def to_s
        "#{full_path}:#{line_num}"
      end
    end

    # One logical unit of one or more presentation pieces, which may span multiple source files.
    #
    class Item
      def initialize(logical_path, scope_class)
        @logical_path = logical_path
        @scope_class = scope_class
        @pieces_by_kind = {}
        @singleton = logical_path.each_filename.all? { |part| part !~ PROP_PATTERN }
        @partial = logical_path.each_filename.any? { |part| part =~ PARTIAL_PATTERN }
      end

      attr_reader :logical_path, :scope_class

      def add_piece(piece)
        Item.verify_kind!(piece.kind)
          
        if existing_piece = @pieces_by_kind[piece.kind]
          raise "Conflicting `#{piece.kind}` piece for item #{self}:" +
            [piece, existing_piece].map { |piece| "\n  in #{piece.source}" }.join
        end

        @pieces_by_kind[piece.kind] = piece
      end

      def self.verify_kind!(kind)
        unless PROCESSING_ORDER.include?(kind)
          raise "Unknown kind of piece: #{kind}"
        end
      end

      PROCESSING_ORDER = [:script, :template, :style]

      def pieces
        PROCESSING_ORDER.map { |kind| @pieces_by_kind[kind] }.compact
      end

      def partial?
        @partial
      end

      def singleton?
        @singleton
      end

      def partial_search_paths
        @partial_search_paths ||= Array(logical_path.ascend.drop(1)) + [Pathname.new('.')]
      end

      def output_path(props:)
        logical_path.gsub_in_components(PROP_PATTERN) do |match|
          prop_spec = match[1]
          key_chain = [:props]
          target = props

          prop_spec.split('.').map(&:to_sym).each do |key|
            error_msg = nil
            begin
              new_target = if target.respond_to?(key)
                target.send(key)
              elsif target.respond_to?(:[])
                target[key]
              end

              unless new_target
                error_msg = "is either missing or nil"
                if target.respond_to?(:keys)
                  error_msg += "; available properties are: #{target.keys.join(', ')}"
                end
              end
            rescue => e
              error_msg = "raised an " + e.class.name + ": " + e.message
            end

            if error_msg
              raise "Unable to resolve property {#{prop_spec}} for item path #{self}:" +
                " #{key} property of #{key_chain.join('.')} " +
                error_msg
            end

            target = new_target
            key_chain << key
          end
          target
        end
      end

      def logical_relative(path)
        (logical_path.parent + path)  # path can be absolute; if it is...
          .strip_leading_slash        # ...turn absolute `/a/b/c` back into logical `a/b/c`
      end

      def prepare!(context)
        pieces.each { |piece| piece.renderer.prepare(context) }
      end

      def to_s
        "❰#{logical_path}❱"
      end

    private

      PARTIAL_PATTERN = /^_/
      PROP_PATTERN = /\{(.*?)\}/
    end

    Piece = ::Data.define(:kind, :source, :renderer)

  end
end
