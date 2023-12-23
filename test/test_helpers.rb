require 'minitest/autorun'
require "minitest/reporters"
require "minitest/focus"
require 'pathname'
require_relative '../lib/project'

class SuperfluousTest < Minitest::Test
  def logger
    NoopLogger.new  # Swallow test output
  end

  class NoopLogger < Superfluous::Logger
    def log(*args)
    end

    def make_last_temporary_permanent
    end
  end
end

# Show names of integration tests instead of unlabeled dots while running tests
#
class CustomReporter < Minitest::Reporters::DefaultReporter
  def before_suite(suite)
  end

  def on_record(result)
    super

    test_path = result.klass.split("::")
    test_path << result.name.gsub(/^test_/, '').gsub('_', ' ')
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
