require_relative 'data'
require_relative 'site'
require_relative 'logging'
require 'awesome_print'

class SSG
  def initialize(project_dir:, live: false)
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
    log_timing("Building", "Build completed") do

      data = log_timing("Reading data", "Read data") do
        read_data(@src_dir + "data")
      end

      if ENV['dump_data']
        log
        log "──────────────────────── Data ────────────────────────"
        log_indented do
          log data.ai(indent: -2, ruby19_syntax: true)
        end
        log "──────────────────────────────────────────────────────"
        log
      end

      log_timing("Processing site", "Processed site") do
        process_site_clean(
          site_dir: @src_dir + "site",
          data: data,
          output_dir: @output_dir)
      end
    end
  end

  def live_serve
    require 'adsf'
    require 'adsf/live'
    require 'listen'

    build

    Listen.to(@src_dir, latency: 0.05, wait_for_delay: 0.2) do
      build
    end.start

    server = Adsf::Server.new(live: true, root: @output_dir)
    %w[INT TERM].each do |s|
      Signal.trap(s) { server.stop }
    end
    server.run
  end
end

live = !!ARGV.delete("--live")
SSG.new(project_dir: ARGV[0], live: live)
