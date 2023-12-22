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
          = partial 'helper' do
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

  def test_missing_partial
    build_and_check_error(
      files: {
        "presentation/a/b/c.haml" => "= partial 'florgblat'"
      },
      expected_message: "No template found for partial florgblat (Searched for a/b/_florgblat.*, a/_florgblat.*, _florgblat.*)",
      expected_in_backtrace: ["《src_dir》/presentation/a/b/c.haml:1:"]
    )
  end

  def test_partial_with_props
    build_and_check_error(
      files: {
        "presentation/main.haml" => "= partial 'helper[oops]'",
        "presentation/_helper[oops].haml" => "%b oops"
      },
      expected_message: "Partial ❰_helper[oops]❱ cannot have [square braces] in its filename",
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
        "presentation/foo[bar].superf" => <<~EOS
          ––– script.rb –––
          def build
            render(baz: 3, blarg: 17)
          end
        EOS
      },
      expected_message: "Prop [bar] appears in item path ❰foo[bar]❱, but no value given for bar; available props are: data, baz, blarg"
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
      expected_message: 'Unsupported script type "frax" at 《src_dir》/presentation/foo.superf:5'
    )
  end

  def test_unsupported_template_type
    build_and_check_error(
      files: {
        "presentation/foo.superf" => "\n\n\n\n\n––– template.frax –––\nyup"
      },
      expected_message: 'Unsupported template type "frax" at 《src_dir》/presentation/foo.superf:6'
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
        "presentation/foo.haml" => "= partial 'bar'",
        "presentation/_bar.haml" => "\n\n\n= yield",
      },
      expected_message: "Template called yield, but no nested content given",
      expected_in_backtrace: ["《src_dir》/presentation/_bar.haml:4:"]
    )
  end

  def test_script_without_build_method
    build_and_check_error(
      files: {
        "presentation/foo.superf" => "\n––– script.rb –––\ndef blag; end",
      },
      expected_message: "Script does not define a `build` method: 《src_dir》/presentation/foo.superf:2"
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
