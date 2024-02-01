require_relative 'data/builder'
require_relative 'presentation/builder'
require_relative 'logging'

module Superfluous
  def self.work_dir(subdir)
    @work_dir_parent ||= Pathname.new(Dir.tmpdir) + "superfluous"
    result = @work_dir_parent + subdir
    result.mkpath
    result
  end

  def self.is_dir_script?(pathname)
    pathname.basename.to_s =~ /^_.*\.rb$/
  end

  def self.read_dir_scripts(dir, parent_class: Object)  # both data and presentation share this
    dir_script_files = dir.children.filter { |f| is_dir_script?(f) }
    if dir_script_files.any?
      return Class.new(parent_class) do |new_scope|
        dir_script_files.each do |script_file|  # TODO: possible to detect conflicting defs?
          new_scope.class_eval(script_file.read, script_file.to_s)
        end
      end
    else
      return parent_class
    end
  end

  ProjectConfig = ::Data.define(:auto_extensions, :index_filenames)

  class Project
    attr_reader :project_dir, :src_dir, :output_dir, :data, :config

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

      # TODO: Make this configurable
      @config = ProjectConfig.new(
        auto_extensions: %w[html],
        index_filenames: %w[index.html],
      )
    end

    def data_dir
      @src_dir + "data"
    end

    def presentation_dir
      @src_dir + "presentation"
    end

    def lib_dir
      @src_dir + "lib"
    end

    def build(use_existing_data: false)
      @logger.log_timing("Building", "Build completed") do
        with_project_load_path do
          @output_dir.mkdir unless @output_dir.exist?

          if use_existing_data && @data
            @logger.log("Using existing data")
          else
            read_data
          end

          @logger.log_timing("Applying presentation", "Presentation applied") do
            Presentation::Builder.new(
              presentation_dir: presentation_dir,
              logger: @logger,
              project_config: @config
            ).build_clean(
              data: @data,
              output_dir: @output_dir
            )
          end
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
    end

    def with_project_load_path(&action)
      original_load_path = $LOAD_PATH
      $LOAD_PATH.unshift(lib_dir) if lib_dir.exist?

      yield

    ensure
      $LOAD_PATH.replace(original_load_path)
    end
  end
end
