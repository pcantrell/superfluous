@log_indent_level = 0

def log(message = "", newline: true)
  @log_indent_level ||= 0  # TODO: fix indentation when logging from setup scope
  message = message.to_s
  if message.include?("\n")
    message.lines.each { |line| log(line.rstrip, newline:) }
    return
  end

  @log_indent_level.times { print "  " }
  print message
  puts if newline
  STDOUT.flush
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
