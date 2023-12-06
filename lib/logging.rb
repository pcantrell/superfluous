module Superfluous
  class Logger
    def initialize
      @log_indent_level = 0
      @log_indent_suppressed = false
    end

    attr_accessor :verbose

    def log(message = "", newline: true, temporary: false)
      message = message.to_s
      if message.include?("\n")
        message.lines.each { |line| log(line.rstrip, newline:, temporary:) }
        return
      end

      print "\eD\eD\eM\eM\e7" if temporary  # scroll window to pre-clear space, then save cursor
      print "\e[K"  # clear to EOL

      unless @log_indent_suppressed
        @log_indent_level.times { print "  " }
      end
      @log_indent_suppressed = !newline unless temporary

      print message
      puts if newline

      print "\e8" if temporary  # restore cursor

      STDOUT.flush
    end

    def make_last_temporary_permanent
      puts
      @log_indent_suppressed = false
    end

    def log_indented
      @log_indent_level += 1
      yield
    ensure
      @log_indent_level -= 1
    end

    def log_timing(start_message, completion_message, &task)
      log start_message + "..."
      timer = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = log_indented { yield }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - timer
      log "✅ #{completion_message} in #{"%0.3f" % elapsed}s"
      result
    end
  end
end
