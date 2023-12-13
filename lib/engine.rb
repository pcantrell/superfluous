require_relative 'data'
require_relative 'site_build'
require_relative 'logging'
require 'awesome_print'

module Superfluous
  class Engine
    attr_reader :project_dir, :src_dir, :output_dir

    def initialize(project_dir:, logger:, output_dir: nil)
      @logger = logger

      @project_dir = Pathname.new(project_dir)
      @src_dir = @project_dir + "src"
      @output_dir =
        if output_dir
          Pathname.new(output_dir)
        else
          @project_dir + "output"
        end
    end

    def build
      @logger.log_timing("Building", "Build completed") do
        data_dir = @src_dir + "data"
        data = if data_dir.exist?
          @logger.log_timing("Reading data", "Read data") do
            data, file_count = Superfluous::Data.read(data_dir, logger: @logger)
            @logger.log "Parsed #{file_count} data files"
            data
          end
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
  end
end
