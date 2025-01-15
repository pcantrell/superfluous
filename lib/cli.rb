require 'optparse'
require 'ansi'
require_relative 'project'

module Superfluous
  class CLI
    def self.run(args)
      args = args.dup  # Save ARGV for self-relaunch

      opt_parser = OptionParser.new do |parser|
        parser.banner = "Usage: superfluous <project-dir> [options]"
        parser.on("-l", "--live", "Start a local web server with live updates on rebuild")
        parser.on("-v", "--verbose", "Show more details during build")
        parser.on("-d", "--data-explorer", "Open an interactive console for exploring data")
        parser.on("-o", "--output DIR", "Put build results in the given directory",
          "WARNING: Deletes all existing contents of the given directory")
      end

      opts = {}
      begin
        opt_parser.parse!(args, into: opts)
        raise "missing project dir argument" if args.length != 1
      rescue => e
        puts
        puts "ERROR: #{e}"
        STDERR.puts opt_parser.help
        exit 1
      end

      opts.transform_keys! { |k| k.to_s.gsub('-', '_').to_sym }  # CLI opts → Ruby kwargs

      Superfluous::CLI.new(project_dir: args[0], **opts)
    end

    def initialize(
      project_dir:,
      output: nil, live: false, verbose: false, data_explorer: false
    )
      logger = Logger.new
      logger.verbose = verbose

      opts = {}
      opts[:output] = output if output
      @project = Project.new(project_dir:, logger:, **opts)

      @data_explorer = data_explorer

      success = build_guarded

      if live || data_explorer
        live_serve
      else
        exit(success ? 0 : 1)
      end
    end
    
    def live_serve
      require 'adsf'
      require 'adsf/live'
      require 'listen'

      # Changes to src/ cause rebuild
      rebuild_on_change(@project.context.data_dir)
      rebuild_on_change(@project.context.presentation_dir, use_existing_data: true)

      # Changes to bundle or to Superfluous itself cause relaunch + rebuild (for development)
      relaunch_on_change("Superfluous gem", Pathname.new(__dir__).parent)
      relaunch_on_change("Gemfile", Pathname.new(ENV['BUNDLE_GEMFILE']).parent, only: /^Gemfile.*/)

      # Start a local web server
      if @data_explorer
        run_data_explorer
      else
        override_web_server_logging!
        @server = Adsf::Server.new(
          live: :manual,
          root: @project.context.output_dir,
          index_filenames: @project.context.index_filenames,
          auto_extensions: @project.context.auto_extensions,
        )
        %w[INT TERM].each do |s|
          Signal.trap(s) { @server.stop }
        end
        @server.run
      end
    end

    def rebuild_on_change(dir, **opts)
      Listen.to(dir, latency: 0.05, wait_for_delay: 0.2) do
        build_guarded(**opts)
      end.start
    end

    def relaunch_on_change(description, dir, **listen_opts)
      Listen.to(dir, **listen_opts) do
        puts
        puts "#{description} modified; relaunching..."
        puts
        exec((Pathname.new(__dir__) + "../bin/superfluous").realpath.to_s, *ARGV)
      end.start
    end

    def build_guarded(**kwargs)
      begin
        if @data_explorer
          @project.read_data
          if @data_explorer_thread
            @data_explorer_thread.raise DataReloaded
          end
        else
          @project.build(**kwargs)
          @server&.live_reload
        end
        return true
      rescue SystemExit, Interrupt
        raise
      rescue Exception => e
        log_failure(e)
        return false
      ensure
        puts
      end
    end

    def log_failure(exception)
      2.times { puts }
      puts "Superfluous build failed"
      trace_file = Superfluous.work_dir("logs") +
        "build-#{Time.now.to_f}-#{exception.class.name.gsub(/:+/, '_')}.log"
      
      File.write(trace_file, exception.full_message(highlight: false))
      puts "  detailed stack trace in: #{trace_file}"
      puts

      puts ANSI.bold { ANSI.red { exception.message } }

      project_dir = @project.context.project_dir.realpath.to_s + "/"
      found_user_context = false
      exception.backtrace_locations.each do |location|
        path = (location.absolute_path || location.path)
        if path.start_with?(project_dir)
          context_path = project_dir
          user_path = path.delete_prefix(project_dir)
          found_user_context = true
        elsif found_user_context
          next
        else
          context_path = path
          user_path = nil
        end

        print ANSI.dark { "  from " }
        print ANSI.yellow { ANSI.dark { context_path } }
        print ANSI.yellow { user_path }
        print ANSI.dark { ":" }
        print ANSI.dark unless user_path
        print ANSI.cyan { location.lineno }
        print ANSI.blue { " (in #{location.label})" }
        puts ANSI.clear
      end
      puts
    end

    def run_data_explorer
      @data_explorer_thread = Thread.current
      loop do
        begin
          dump_data if @data_explorer_path
        rescue => e
          puts e.full_message
        end

        puts
        @data_explorer_path ||= []
        path_str = @data_explorer_path.map { |k| k =~ /^\d+$/ ? "[#{k}]" : ".#{k}"}.join
        print ANSI.green("data" + path_str + ANSI.dark("> "))
        STDOUT.flush
        new_path = STDIN.readline.strip
        puts

        while new_path.start_with?("..")
          @data_explorer_path.pop
          new_path[0] = ""
        end
        if new_path =~ /^data(\.|$)/
          new_path.delete_prefix!('data')
          @data_explorer_path = []
        end
        @data_explorer_path += new_path
          .split(/[\[\]\.]/)
          .reject(&:blank?)
      rescue DataReloaded
        # Restart from the top
      end
    end

    def dump_data
      target = @project.data
      @data_explorer_path.each do |attr|
        puts "→ #{attr}"
        attr = attr.to_i if target.is_a?(Array)
        target = target[attr]
      end

      print ANSI.red("(#{target.class}) ")
      case target
        when Superfluous::Data::Dict
          puts "{"
          target.each_pair do |k, v|
            puts "  #{k}: #{ANSI.blue(truncate(v.to_s))}"
            STDOUT.flush
          end
          puts "}"
        when Array
          puts "["
          target.each.with_index do |elem, index|
            puts "  #{index}: #{ANSI.blue(truncate(elem.to_s))}"
          end
          puts "]"
        else
          puts ANSI.blue(target)
      end
    end

    def truncate(s)
      if s.length > 80
        s[0...80] + "..."
      else
        s
      end.gsub("\n", "\\n")
    end

    # Turn back! Only horrifying monkey patches lie beyond this point.

    def override_web_server_logging!
      # Wrap Rack’s logging with our colorizer
      ::Rack::CommonLogger.prepend(RackLogOverride)

      # Hack to colorize adsf’s startup message with the site URL
      ::Adsf::Server.prepend(AdsfLogOverride)
    end

    class DataReloaded < Exception; end

    module RackLogOverride
      LOG_MUTEX = Mutex.new

      def log(env, status, *args)
        LOG_MUTEX.synchronize do  # ensure colors are attached to correct log line
          if status >= 400
            print ANSI.red + ANSI.bold
          elsif status == 304
            print ANSI.dark
          elsif status >= 300
            print ANSI.yellow
          end
          super(env, status, *args)  # Rack’s actual log method
        ensure
          print ANSI.clear
        end
      end
    end

    module AdsfLogOverride
      def puts(*args)
        if args[0] =~ /(View the site at )(.*)/
          Kernel::puts ANSI.blue { $1 + ANSI.bold { $2 } }
          Kernel::puts args[1..]
          Kernel::puts
        else
          Kernel::puts(*args)
        end
      end
    end

  end
end
