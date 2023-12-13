require_relative 'engine'

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

      @engine = Engine.new(project_dir:, logger:)

      if live
        live_serve
      else
        build_guarded
      end
    end
    
    def live_serve
      require 'adsf'
      require 'adsf/live'
      require 'listen'

      build_guarded

      Listen.to(@engine.src_dir, latency: 0.05, wait_for_delay: 0.2) do
        build_guarded
      end.start

      Listen.to(Pathname.new(__dir__).parent) do
        puts
        puts "Superfluous gem modified; relaunching..."
        puts
        exec((Pathname.new(__dir__) + "../bin/superfluous").realpath.to_s, *ARGV)
      end.start

      server = Adsf::Server.new(live: true, root: @engine.output_dir)
      %w[INT TERM].each do |s|
        Signal.trap(s) { server.stop }
      end
      server.run
    end

    def build_guarded
      begin
        puts
        @engine.build
      rescue SystemExit, Interrupt
        raise
      rescue ::Superfluous::BuildFailure => e
        flag_failure(e.cause)
        puts e.message
      rescue Exception => e
        flag_failure(e)
        puts e.full_message(highlight: true)
      ensure
        puts
      end
    end

    def flag_failure(exception)
      2.times { puts }
      puts "Superfluous build failed"
      trace_file = Superfluous.work_dir("logs") +
        "build-#{Time.now.to_f}-#{exception.class.name.gsub(/:+/, '_')}.log"
      File.write(trace_file, exception.full_message(highlight: false))
      puts "  detailed trace in: #{trace_file}"
      puts
    end
  end
end
