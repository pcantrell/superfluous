require 'ansi'
require_relative 'project'

module Superfluous
  class CLI
    def self.run(args)
      args = args.dup  # Save ARGV for self-relaunch
      live = !!args.delete("--live")
      verbose = !!args.delete("--verbose")
      inspect_data = !!args.delete("--inspect-data")

      usage_and_exit! if args.length != 1

      Superfluous::CLI.new(project_dir: args[0], live:, verbose:, inspect_data:)
    end

    def self.usage_and_exit!
      STDERR.puts "usage: superfluous <project-dir> [--live] [--verbose]"
      exit 1
    end

    def initialize(project_dir:, live:, verbose:, inspect_data:)
      logger = Logger.new
      logger.verbose = verbose

      @project = Project.new(project_dir:, logger:)

      @inspect_data = inspect_data

      build_guarded

      live_serve if live || inspect_data
    end
    
    def live_serve
      require 'adsf'
      require 'adsf/live'
      require 'listen'

      # Changes to src/ cause rebuild
      rebuild_on_change(@project.data_dir)
      rebuild_on_change(@project.presentation_dir, use_existing_data: true)

      # Changes to bundle or to Superfluous itself cause relaunch + rebuild (for development)
      relaunch_on_change("Superfluous gem", Pathname.new(__dir__).parent)
      relaunch_on_change("Gemfile", Pathname.new(ENV['BUNDLE_GEMFILE']).parent, only: /^Gemfile.*/)

      # Start a local web server
      if @inspect_data
        interactive_inspect_data
      else
        override_web_server_logging!
        server = Adsf::Server.new(
          live: true,
          root: @project.output_dir,
          index_filenames: @project.config.index_filenames,
          auto_extensions: @project.config.auto_extensions,
        )
        %w[INT TERM].each do |s|
          Signal.trap(s) { server.stop }
        end
        server.run
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
        if @inspect_data
          @project.read_data
          if @inspect_data_thread
            @inspect_data_thread.raise DataReloaded
          end
        else
          @project.build(**kwargs)
        end
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

    def interactive_inspect_data
      @inspect_data_thread = Thread.current
      loop do
        begin
          dump_data if @inspect_data_path
        rescue => e
          puts e.full_message
        end

        puts
        @inspect_data_path ||= []
        path_str = @inspect_data_path.map { |k| k =~ /^\d+$/ ? "[#{k}]" : ".#{k}"}.join
        print ANSI.green("data" + path_str + ANSI.dark("> "))
        STDOUT.flush
        new_path = STDIN.readline.strip
        puts

        while new_path.start_with?("..")
          @inspect_data_path.pop
          new_path[0] = ""
        end
        if new_path =~ /^data(\.|$)/
          new_path.delete_prefix!('data')
          @inspect_data_path = []
        end
        @inspect_data_path += new_path
          .split(/[\[\]\.]/)
          .reject(&:blank?)
      rescue DataReloaded
        # Restart from the top
      end
    end

    def dump_data
      target = @project.data
      @inspect_data_path.each do |attr|
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
      # Disable WEBrick’s logging completely; only use Rack logs
      WEBrick::Config::HTTP[:AccessLog] = []

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
