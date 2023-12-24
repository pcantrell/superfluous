require 'tilt'
require 'active_support/all'
require 'tmpdir'
require_relative 'renderers'
require_relative '../extensions'

module Superfluous
  module Presentation
    # Retains compiled scripts and templates, so create a new instance to pick up changes.
    #
    class Builder
      def initialize(presentation_dir:, logger:)
        raise "#{presentation_dir.to_s} is not a directory" unless presentation_dir.directory?

        @presentation_dir = presentation_dir
        @logger = logger

        @items_by_logical_path = {}  # logical path → Item
        Pathname.glob("**/*", base: presentation_dir) do |relative_path|
          source = Source.new(root_dir: presentation_dir, relative_path:)
          next if source.full_path.directory?

          Renderer.each_piece(source) do |logical_path:, piece:|
            item = @items_by_logical_path[logical_path] ||=
              Item.new(logical_path, Class.new(Renderer::RenderingScope))
            item.add_piece(piece)
          end
        end
      end

      # Renders a new version of the output to a tmp dir, then quickly swaps out the out entire
      # contents of the actual output dir with the completed results.
      #
      def build_clean(output_dir:, **kwargs)
        Dir.mktmpdir do |tmp_dir|
          tmp_dir = Pathname.new(tmp_dir)

          build(output_dir: tmp_dir, **kwargs)

          Dir.mktmpdir do |old_output|
            FileUtils.mv output_dir.children, old_output
            FileUtils.mv tmp_dir.children, output_dir
          end
        end
      end

      # Traverses and processes the presentation/ directory, replacing existing files in the output
      # dir but leaving any extraneous / straggler files untouched.
      #
      def build(data:, output_dir:)
        output_dir = output_dir.realpath
        @items_by_logical_path.values.each do |item|
          next if item.partial?

          log_item_processing(item) do |log_output_file:|
            build_item(item, data:) do |context|
              output_file_relative = item.output_path(props: context.props)
              log_output_file.call(output_file_relative)
              output_file = (output_dir + output_file_relative).cleanpath
              unless output_dir.contains?(output_file)
                raise "Item produced a dynamic output path that lands outsite the output folder" +
                  "\n  relative output path: #{output_file_relative}" +
                  "\n           resolved to: #{output_file}" +
                  "\n   which is outside of: #{output_dir}"
              end

              unless content = context.props[:content]
                raise "Pipeline did not produce a `content` prop for #{item}. When an item has" +
                  " only a script and no template, the script must call `render(content: ...)`."
              end

              output_file.parent.mkpath
               File.write(output_file, content)
            end
          end
        end
      end

    private

      def build_item(item, data:, props: {}, nested_content: nil, &final_step)
        check_output_count(item) do |count_output|
          final_step_with_count = lambda do |*args|
            count_output.call
            final_step.call(*args)
          end

          pipeline = item.pieces.reverse.reduce(final_step_with_count) do |next_pipeline_step, piece|
            lambda do |context|  # context here will come from previous steps
              context = context.with(
                scope: item.scope_class.new(context:, next_pipeline_step:))
              piece.renderer.render(context, &next_pipeline_step)
            end
          end

          pipeline.call(
            Renderer::Context.new(
              props: { data: }.merge(props),
              scope: nil,  # each pipeline step will get its own scope object
              nested_content:,
              partial_renderer: lambda do |partial, **props, &block|
                render_partial(partial, from_item: item, data:, **props, &block)
              end
            )
          )
        end
      end

      def check_output_count(item, &build)
        output_count = 0

        yield(Proc.new do
          output_count += 1
          if item.singleton? && output_count > 1
            raise "Singleton #{item} attempted to render multiple times"
          end
        end)

        if item.singleton? && output_count != 1
          raise "Singleton #{item} rendered #{output_count} times, but should have rendered" +
            " exactly once. The most common cause for this is a script never calling `render`."
        end
      end

      # Messy logic for a simple purpose: show a nicely formatted build tree, with multi-output
      # files collapsed when not in verbose mode.
      #
      def log_item_processing(item)
        @logger.log item.logical_path, newline: false
        subsequent_line_prefix = nil
        output_count = 0

        yield(
          log_output_file: Proc.new do |output_file_relative|
            if output_count == 0 || @logger.verbose
              if subsequent_line_prefix
                @logger.log subsequent_line_prefix, newline: false
              else
                subsequent_line_prefix = " " * item.logical_path.to_s.size
              end
            end
            @logger.log " → #{output_file_relative}", temporary: !@logger.verbose
            output_count += 1
          end
        )

        @logger.log "  ⚠️  no output", temporary: !@logger.verbose if output_count == 0
        if !@logger.verbose
          @logger.make_last_temporary_permanent
          if output_count > 1
            @logger.log "#{subsequent_line_prefix} → …#{output_count - 1} more…"
          end
        end
      end

      def render_partial(partial, from_item:, data:, **props, &nested_content)
        from_item.partial_search_paths.each do |search_path|
          if partial_item = @items_by_logical_path[search_path + "_#{partial}"]
            unless partial_item.singleton?
              raise "Partial #{partial_item} cannot have [square braces] in its filename"
            end

            result = nil
            build_item(partial_item, data:, props:, nested_content:) do |context|
              result = context.props[:content].html_safe
            end
            return result
          end
        end
        searched_paths = from_item.partial_search_paths.map { |path| path + "_#{partial}.*" }
        raise "No template found for partial #{partial} (Searched for #{searched_paths.join(', ')})"
      end
    end
  end
end