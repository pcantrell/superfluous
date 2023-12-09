require 'minitest/autorun'
require 'pathname'
require 'diffy'
require_relative '../lib/cli.rb'

class IntegrationTest < Minitest::Test
  (Pathname.new(__dir__) + "integration").each_child do |test_dir|
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
    if expected.strip != actual.strip
      diff = Diffy::Diff.new(expected, actual).to_s(:color)
        .gsub(/\e\[3([12])m/) { "\e\[3#{3 - $1.to_i}m" }  # Swap red and green
      fail "Data mismatch:\n#{diff}"
    end
  end

  def format_data(data, indent = "")
    result = "(#{data.class.name}) "
    case data
      when OpenStruct
        result << "{\n"
        data.each_pair do |key, value|
          result << "#{indent}  #{key}: "
          result << format_data(value, indent + "  ")
        end
        result << indent + "}\n"
      when Array
        result << "[\n"
        data.each do |elem|
          result << indent + "  "
          result << format_data(elem, indent + "  ")
        end
        result << indent + "]\n"
      else
        result << data.inspect
        result << "\n"
    end
    result
  end

  def run_output_test(project_dir, expected_output)
  end

  def logger
    NoopLogger.new
  end

  class NoopLogger < Superfluous::Logger
    def log(*args)
      # noop
    end
  end
end
