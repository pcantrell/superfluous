require_relative 'test_helpers'

class ErrorTest < SuperfluousTest
  def setup
    @project_dir = Pathname.new(Dir.mktmpdir).realpath
  end

  def teardown
    FileUtils.remove_entry(@project_dir)
  end

  def test_syntax_error_in_script
    build_and_check_error(
      files: {
        "presentation/syntax_error.superf" => <<~EOF
          ––– script.rb –––
          def build
            render(
          end
          ––– template.haml –––
        EOF
      },
      exception: SyntaxError,
      expected_message: "《src_dir》/presentation/syntax_error.superf:4: syntax error,",
    )
  end

  def test_exception_in_script
    build_and_check_error(
      files: {
        "presentation/exception.superf" => <<~EOF
          ––– script.rb –––
          def build
            make_error
          end

          def make_error
            raise "boom"
          end
          ––– template.haml –––
        EOF
      },
      expected_message: "boom",
      expected_in_backtrace: [
        "《src_dir》/presentation/exception.superf:7:",
        "《src_dir》/presentation/exception.superf:3:",
      ]
    )
  end

  def test_exception_in_template
    build_and_check_error(
      files: {
        "presentation/exception.haml" => <<~EOF
          %ul
            %li= raise "splat"
        EOF
      },
      expected_message: "splat",
      expected_in_backtrace: [
        "《src_dir》/presentation/exception.haml:2:",
      ]
    )
  end

  def test_exception_deep_trace
    build_and_check_error(
      files: {
        "presentation/exception.superf" => <<~EOF
          ––– script.rb –––
          def build
            render
          end

          def helper
            raise 'whoosh'
          end
          ––– template.haml –––
          = partial '_helper' do
            - helper
        EOF
      }.merge(
        "presentation/_helper.superf" => <<~EOF
          ––– script.rb –––
          def build
            render
          end
          ––– template.haml –––
          %h1= yield
        EOF
      ),
      expected_message: "whoosh",
      expected_in_backtrace: [
        "《src_dir》/presentation/exception.superf:7:",
        "《src_dir》/presentation/exception.superf:11:",
        "《src_dir》/presentation/_helper.superf:6:",
        "《src_dir》/presentation/_helper.superf:3:",
        "《src_dir》/presentation/exception.superf:10:",
        "《src_dir》/presentation/exception.superf:3:",
      ]
    )
  end

  def test_no_render
    build_and_check_error(
      files: {
        "presentation/no-render.superf" => <<~EOF
          ––– script.rb –––
          def build;end
          ––– template.haml –––
        EOF
      },
      expected_message: "Singleton ❰no-render❱ rendered 0 times, but should have rendered exactly once"
    )
  end

  def test_double_render
    build_and_check_error(
      files: {
        "presentation/foo/double-render.superf" => <<~EOF
          ––– script.rb –––
          def build
            render(foo: 1)
            render(bar: 2)
          end
          ––– template.haml –––
        EOF
      },
      expected_message: "Singleton ❰foo/double-render❱ attempted to render multiple times",
      expected_in_backtrace: ["《src_dir》/presentation/foo/double-render.superf:4:"]
    )
  end

  def test_no_render_in_partial
    build_and_check_error(
      files: {
        "presentation/_no-render.superf" => <<~EOF
          ––– script.rb –––
          def build; end
          ––– template.haml –––
          partial here
        EOF
      }.merge(
        "presentation/main.superf" => <<~EOF
          ––– template.haml –––
          %p= partial '_no-render'
        EOF
      ),
      expected_message: "Singleton ❰_no-render❱ rendered 0 times, but should have rendered exactly once",
      expected_in_backtrace: ["《src_dir》/presentation/main.superf:2:"]
    )
  end

  def test_double_render_in_partial
    build_and_check_error(
      files: {
        "presentation/_double-render.superf" => <<~EOF
          ––– script.rb –––
          def build
            render(foo: 1)
            render(foo: 2)
          end
          ––– template.haml –––
          partial here \#{foo}
        EOF
      }.merge(
        "presentation/main.superf" => <<~EOF
          ––– template.haml –––
          %p= partial '_double-render'
        EOF
      ),
      expected_message: "Singleton ❰_double-render❱ attempted to render multiple times",
      expected_in_backtrace: [
        "《src_dir》/presentation/_double-render.superf:4:",
        "《src_dir》/presentation/main.superf:2:",
      ]
    )
  end

  def test_no_content
    build_and_check_error(
      files: {
        "presentation/no-content.superf" => <<~EOF
          ––– script.rb –––
          def build
            render
          end
        EOF
      },
      expected_message: "Pipeline did not produce a `content` prop for ❰no-content❱",
      expected_in_backtrace: ["《src_dir》/presentation/no-content.superf:3:"]
    )
  end

  def test_no_content_on_second_render
    # The helps test that props from one render don't propagate to the next
    build_and_check_error(
      files: {
        "presentation/no-content-{n}.superf" => <<~EOF
          ––– script.rb –––
          def build
            render(n: 1, content: "")
            render(n: 2)
          end
        EOF
      },
      expected_message: "Pipeline did not produce a `content` prop for ❰no-content-{n}❱",
      expected_in_backtrace: ["《src_dir》/presentation/no-content-{n}.superf:4:"]
    )
  end

  def test_dynamic_path_escapes_output_folder
    build_and_check_error(
      files: {
        "presentation/{path}.superf" => <<~EOF
          ––– script.rb –––
          def build
            render(path: "./foo", content: "")  # OK
            render(path: "../bar", content: "") # Not OK
          end
        EOF
      },
      expected_message: "Item produced a dynamic output path that lands outsite the output folder",
      expected_in_backtrace: ["《src_dir》/presentation/{path}.superf:4:"]
    )
  end

  def test_missing_partial
    build_and_check_error(
      files: {
        "presentation/a/b/c.haml" => "= partial '_florgblat'"
      },
      expected_message: "No template found for partial _florgblat (Searched for a/b/_florgblat.*, a/_florgblat.*, _florgblat.*)",
      expected_in_backtrace: ["《src_dir》/presentation/a/b/c.haml:1:"]
    )
  end

  def test_partial_with_props
    build_and_check_error(
      files: {
        "presentation/main.haml" => "= partial '_helper{oops}'",
        "presentation/_helper{oops}.haml" => "%b oops"
      },
      expected_message: "Partial ❰_helper{oops}❱ cannot have {curly braces} in its filename",
      expected_in_backtrace: ["《src_dir》/presentation/main.haml:1:"]
    )
  end

  def test_unknown_piece
    build_and_check_error(
      files: {
        "presentation/foo.superf" => "––– glomple.haml –––"
      },
      expected_message: "Unknown kind of piece: glomple"
    )
  end

  def test_conflicting_piece
    build_and_check_error(
      files: {
        "presentation/foo.superf" => "\n\n\n––– template.haml –––",
        "presentation/foo.haml" => ""
      },
      expected_message: <<~EOS
        Conflicting `template` piece for item ❰foo❱:
          in 《src_dir》/presentation/foo.superf:4
          in 《src_dir》/presentation/foo.haml:1
      EOS
    )
  end

  def test_missing_filename_prop
    build_and_check_error(
      files: {
        "presentation/foo{bar}.superf" => <<~EOS
          ––– script.rb –––
          def build
            render(baz: 3, blarg: 17)
          end
        EOS
      },
      expected_message: "Unable to resolve property {bar} for item path ❰foo{bar}❱: bar property of props is either missing or nil; available properties are: data, baz, blarg"
    )
  end

  def test_missing_nested_filename_prop
    build_and_check_error(
      files: {
        "presentation/foo{bar.baz}.superf" => <<~EOS
          ––– script.rb –––
          def build
            render(bar: { zoof: 3 })
          end
        EOS
      },
      expected_message: "Unable to resolve property {bar.baz} for item path ❰foo{bar.baz}❱: baz property of props.bar is either missing or nil; available properties are: zoof"
    )
  end

  def test_exception_from_filename_prop
    build_and_check_error(
      files: {
        "presentation/foo{bar.baz.include?}.superf" => <<~EOS
          ––– script.rb –––
          def build
            render(bar: { baz: "hello" })
          end
        EOS
      },
      expected_message: "Unable to resolve property {bar.baz.include?} for item path ❰foo{bar.baz.include?}❱: include? property of props.bar.baz raised an ArgumentError: wrong number of arguments (given 0, expected 1)"
    )
  end

  def test_url_of_nonexistent_item
    build_and_check_error(
      files: {
        "presentation/foo.superf" => <<~EOS
          ––– script.rb –––
          def build
            render(content: url(:bar))
          end
        EOS
      }.merge(
        "presentation/other.superf" => <<~EOS
          ––– script.rb –––
          def self.id
            :baz
          end

          def build
            render(content: "hi")
          end
        EOS
      ),
      expected_message: "No item has the ID :bar\nAvailable item IDs: [:baz]"
    )
  end

  def test_url_with_missing_param
    build_and_check_error(
      files: {
        "presentation/foo{bar}.superf" => <<~EOS
          ––– script.rb –––
          def self.id
            :foo
          end

          def build
            render(content: url(:foo))
          end
        EOS
      },
      expected_message: "Unable to resolve property {bar} for item path ❰foo{bar}❱"
    )
  end

  def test_illegal_content_before_fence
    build_and_check_error(
      files: {
        "presentation/foo.superf" => "nope\n––– template.erb –––\nyup"
      },
      expected_message: <<~EOS
        Illegal content before first –––fence––– at 《src_dir》/presentation/foo.superf:1:
          "nope\\n"
      EOS
    )
  end

  def test_malformed_fence
    [
      "\n\n–––",
      "\n\n---",
      "\n\n--- ---",
      "\n\n––– no_dot –––",
      "\n\n––– dot.dot.dot –––",
      "\n\n––– space before.dot –––",
      "\n\n––– space.after dot –––",
      "\n\n––– no_closer.erb",
      "\n\n––– closer_too_short.erb ––",
      "\n\n––– template.erb ––– text after fence",
      "––– script.rb –––\ndef build; end\n––– template.erb –––second is malformed",
    ].each do |malformed|
      build_and_check_error(
        files: { "presentation/foo.superf" => malformed },
        expected_message: "Malformed fence at 《src_dir》/presentation/foo.superf:3"
      )
    end
  end

  def test_unsupported_script_type
    build_and_check_error(
      files: {
        "presentation/foo.superf" => "\n\n\n\n––– script.frax –––\nyup"
      },
      expected_message: 'Unsupported script extension ".frax" at 《src_dir》/presentation/foo.superf:5'
    )
  end

  def test_yield_without_nested_content
    build_and_check_error(
      files: {
        "presentation/foo.haml" => "%ul\n  %li= yield"
      },
      expected_message: "Template called yield, but no nested content given",
      expected_in_backtrace: ["《src_dir》/presentation/foo.haml:2:"]
    )
  end

  def test_yield_from_partial_without_nested_content
    build_and_check_error(
      files: {
        "presentation/foo.haml" => "= partial '_bar'",
        "presentation/_bar.haml" => "\n\n\n= yield",
      },
      expected_message: "Template called yield, but no nested content given",
      expected_in_backtrace: ["《src_dir》/presentation/_bar.haml:4:"]
    )
  end

  def test_data_not_a_dir
    build_and_check_error(
      files: { "data" => "" },
      expected_message: "《src_dir》/data is not a directory"
    )
  end

  def test_presentation_not_a_dir
    build_and_check_error(
      files: { "presentation" => "" },
      expected_message: "《src_dir》/presentation is not a directory"
    )
  end

  def test_data_conflict
    build_and_check_error(
      files: {
        "data/foo.json" => '{ "bar": { "baz": 17 } }',
        "data/foo/bar.json" => '{ "baz": 7 }',
      },
      expected_message: "Cannot merge data for baz:\n  value 1: 17 \n  value 2: 7"
    )
  end

  def build_and_check_error(files:, exception: Exception, expected_message:, expected_in_backtrace: [])
    src_dir = (@project_dir + "src").to_s

    error = assert_raises(exception) { build_project(files) }
    actual_message = error.message.gsub(src_dir, "《src_dir》")
    unless actual_message.strip.start_with?(expected_message.strip)
      fail "Mismatched message" +
        "\n  Expected: #{expected_message.inspect}" +
        "\n  Actual:   #{actual_message.inspect}"
    end

    backtrace_remaining = error.backtrace.map do |line|
      line.gsub(src_dir, "《src_dir》")
    end
    expected_in_backtrace.each do |expected_line|
      unless match_index = backtrace_remaining.index { |line| line.start_with?(expected_line) }
        fail "Did not find #{expected_line.inspect} in remaining backtrace lines:\n" +
          backtrace_remaining.map(&:inspect).join("\n")
      end
      backtrace_remaining.slice!(0, match_index + 1)
    end
  end

  def build_project(files)
    files.each do |relative_path, content|
      out_path = @project_dir + "src" + relative_path
      out_path.parent.mkpath
      File.write(out_path, content)
    end
    Superfluous::Project.new(project_dir: @project_dir, logger:).build
  end
end
