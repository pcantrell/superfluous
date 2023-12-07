require_relative 'data'
require_relative 'site_build'
require_relative 'logging'
require 'awesome_print'

module Superfluous
  class CLI
    def initialize(project_dir:, live: false, verbose: false)
      @logger = Logger.new
      @logger.verbose = verbose

      @project_dir = Pathname.new(project_dir)
      @src_dir = @project_dir + "src"
      @output_dir = @project_dir + "output"

      if live
        live_serve
      else
        build
      end
    end

    def build
      @logger.log_timing("Building", "Build completed") do

        data = @logger.log_timing("Reading data", "Read data") do
          data, file_count = Superfluous::Data.read(@src_dir + "data", logger: @logger)
          @logger.log "Parsed #{file_count} data files"
          data
        end

        if ENV['dump_data']
          @logger.log
          @logger.log "──────────────────────── Data ────────────────────────"
          @logger.log_indented do
            @logger.log data.ai(indent: -2, ruby19_syntax: true)
          end
          @logger.log "──────────────────────────────────────────────────────"
          @logger.log
        end

        @logger.log_timing("Processing site", "Processed site") do
          build = SiteBuild.new(logger: @logger)
          build.process_site_clean(
            data:,
            site_dir: @src_dir + "site",
            output_dir: @output_dir)
        end
      end
    end

    def live_serve
      require 'adsf'
      require 'adsf/live'
      require 'listen'

      build_guarded

      Listen.to(@src_dir, latency: 0.05, wait_for_delay: 0.2) do
        build_guarded
      end.start

      Listen.to(Pathname.new(__dir__).parent) do
        puts
        puts "Superfluous gem modified; relaunching..."
        puts
        exec("ruby", __FILE__, *ARGV)
      end.start

      server = Adsf::Server.new(live: true, root: @output_dir)
      %w[INT TERM].each do |s|
        Signal.trap(s) { server.stop }
      end
      server.run
    end

    def build_guarded
      begin
        puts
        build
        puts
      rescue SystemExit, Interrupt
        raise
      rescue Exception => e
        puts
        puts e.full_message(highlight: true)
      end
    end
  end
end

args = ARGV.dup  # Save ARGV for self-relaunch
live = !!args.delete("--live")
verbose = !!args.delete("--verbose")
Superfluous::CLI.new(project_dir: args[0], live:, verbose:)
