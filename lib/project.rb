require_relative 'data'
require_relative 'presentation/builder'
require_relative 'logging'
require 'awesome_print'

module Superfluous
  def self.work_dir(subdir)
    @work_dir_parent ||= Pathname.new(Dir.tmpdir) + "superfluous"
    result = @work_dir_parent + subdir
    result.mkpath
    result
  end

  class Project
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

    def data_dir
      @data_dir ||= @src_dir + "data"
    end

    def presentation_dir
      @src_dir + "presentation"
    end

    def build(use_existing_data: false)
      @logger.log_timing("Building", "Build completed") do
        @output_dir.mkdir unless @output_dir.exist?

        if use_existing_data && @data
          @logger.log("Using existing data")
        else
          read_data
        end

        @logger.log_timing("Applying presentation", "Presentation applied") do
          Presentation::Builder.new(presentation_dir: presentation_dir, logger: @logger)
            .build_clean(data: @data, output_dir: @output_dir)
        end
      end
    end

    def read_data
      @data = if data_dir.exist?
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
    end
  end
end
