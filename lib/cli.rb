require 'ansi'
require_relative 'project'

module Superfluous
  class CLI
    def self.run(args)
      args = args.dup  # Save ARGV for self-relaunch
      live = !!args.delete("--live")
      verbose = !!args.delete("--verbose")
      Superfluous::CLI.new(project_dir: args[0], live:, verbose:)
    end

    def initialize(project_dir:, live:, verbose:)
      logger = Logger.new
      logger.verbose = verbose

      @project = Project.new(project_dir:, logger:)

      build_guarded

      live_serve if live
    end
    
    def live_serve
      require 'adsf'
      require 'adsf/live'
      require 'listen'

      # Changes to site cause rebuild
      Listen.to(@project.src_dir, latency: 0.05, wait_for_delay: 0.2) do
        build_guarded
      end.start

      # Changes to Superfluous itself cause relaunch + rebuild (for development)
      Listen.to(Pathname.new(__dir__).parent) do
        puts
        puts "Superfluous modified; relaunching..."
        puts
        exec((Pathname.new(__dir__) + "../bin/superfluous").realpath.to_s, *ARGV)
      end.start

      # Start a local web server
      override_web_server_logging!
      server = Adsf::Server.new(live: true, root: @project.output_dir)
      %w[INT TERM].each do |s|
        Signal.trap(s) { server.stop }
      end
      server.run
    end

    def build_guarded
      begin
        @project.build
      rescue SystemExit, Interrupt
        raise
      rescue Exception => e
        log_failure(e)
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

      full_src_dir = @project.src_dir.realpath.to_s + "/"
      found_user_context = false
      exception.backtrace_locations.each do |location|
        path = (location.absolute_path || location.path)
        if path.start_with?(full_src_dir)
          context_path = full_src_dir
          user_path = path.delete_prefix(full_src_dir)
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

    # Turn back! Only horrifying monkey patches lie beyond this point.

    def override_web_server_logging!
      # Disable WEBrick’s logging completely; only use Rack logs
      WEBrick::Config::HTTP[:AccessLog] = []

      # Wrap Rack’s logging with our colorizer
      ::Rack::CommonLogger.prepend(RackLogOverride)

      # Hack to colorize adsf’s startup message with the site URL
      ::Adsf::Server.prepend(AdsfLogOverride)
    end

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
