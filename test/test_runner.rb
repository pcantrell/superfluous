require 'minitest/autorun'
require "minitest/reporters"
require 'pathname'
require 'diffy'
require_relative '../lib/cli.rb'

class IntegrationTest < Minitest::Test
  TESTS_DIR = Pathname.new(__dir__) + "integration"

  TESTS_DIR.each_child do |test_dir|
    next if test_dir.basename.to_s.start_with?(".")

    define_method("test_#{test_dir.basename}") do
      run_data_test(test_dir + "data", test_dir + "expected_data")
      run_output_test(test_dir, test_dir + "expected_output")
    end
  end

private

  def run_data_test(data_dir, expected_data_file)
    return unless expected_data_file.exist?

    data, file_count = Superfluous::Data.read(data_dir, logger:)

    expected = expected_data_file.read
    actual = "#{file_count} files\n\n" + format_data(data)
    assert_text_equal(expected, actual)
  end

  def format_data(data, indent = "")
    result = "(#{data.class.name}) "
    case data
      when OpenStruct
        result << "{\n"
        data.each_pair.sort.each do |key, value|
          result << "#{indent}  #{key}: "
          result << format_data(value, indent + "  ")
        end
        result << indent << "}\n"
      when Array
        result << "[\n"
        data.each do |elem|
          result << indent + "  "
          result << format_data(elem, indent + "  ")
        end
        result << indent << "]\n"
      when Pathname
        result << data.to_s.gsub(TESTS_DIR.to_s, "<project_dir>").inspect << "\n"
      else
        result << data.inspect << "\n"
    end
    result
  end

  def run_output_test(project_dir, expected_output)
    return unless expected_output.exist?

    Dir.mktmpdir do |actual_output|
      Superfluous::CLI.new(project_dir:, output_dir: actual_output, logger:)
      assert_dirs_equal(expected_output, actual_output)
    end
  end

  def assert_dirs_equal(expected_dir, actual_dir)
    expected_files, actual_files = [expected_dir, actual_dir].map do
      |dir| Pathname.glob('**', base: dir)
    end
    assert_text_equal expected_files.join("\n"), actual_files.join("\n")

    expected_files.zip(actual_files).each do |expected, actual|
      assert_file_equal(
        Pathname.new(expected_dir) + expected,
        Pathname.new(actual_dir) + actual)
    end
  end

  def assert_file_equal(expected, actual)
    expected_data = expected.read
    actual_data = actual.read
    if [expected_data, actual_data].all?(&:valid_encoding?)  # TODO: implement better binary file detection
      assert_text_equal(expected_data, actual_data)
    else
      assert_equal(expected.binread, actual.binread)
    end
  rescue => e
    puts "ERROR while comparing #{expected} to #{actual}"
    raise
  end

  def assert_text_equal(expected, actual)
    if expected.strip != actual.strip
      diff = Diffy::Diff.new(expected + "\n", actual + "\n").to_s(:color)
        .gsub(/\e\[3([12])m/) { "\e\[3#{3 - $1.to_i}m" }  # Swap red and green
      fail "Data mismatch:\n#{diff}"
    end
  end

  def logger
    NoopLogger.new
  end

  class NoopLogger < Superfluous::Logger
    def log(*args)
    end

    def make_last_temporary_permanent
    end
  end
end


class CustomReporter < Minitest::Reporters::DefaultReporter
  def before_suite(suite)
  end

  def on_record(result)
    super

    test_path = result.klass.split("::")
    test_path << result.name.gsub(/^test_/, '')
    print " "
    color = if result.skipped?
      method(:yellow)
    elsif result.failure
      method(:red)
    else
      :itself
    end
    puts test_path.map(&color).join(blue(" · "))
  end

  def record_pass(record)
    green("✔︎")
  end

  def record_skip(record)
    yellow("S")
  end

  def record_failure(record)
    red("✖︎")
  end
end

unless ENV['RM_INFO']  # RubyMine has its own way of handling test results
  Minitest::Reporters.use! CustomReporter.new
end
