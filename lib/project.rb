require 'git'
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

  ProjectContext = ::Data.define(
    :project_dir,
    :data_dir,
    :presentation_dir,
    :lib_dir,
    :output_dir,

    :auto_extensions,
    :index_filenames,

    :logger,
  )

  DEFAULT_CONFIG = {
    data:         "src/data",
    presentation: "src/presentation",
    lib:          "src/lib",
    output:       "output",
    auto_extensions: %w[html],
    index_filenames: %w[index.html],
  }

  class Project
    attr_reader :project_dir, :data, :context

    def initialize(project_dir:, logger:, **config)
      project_dir = Pathname.new(project_dir)

      config = DEFAULT_CONFIG.merge(config) # TODO: Add project-level config file

      @context = ProjectContext.new(
        project_dir:,
        data_dir:         project_dir + config[:data],
        presentation_dir: project_dir + config[:presentation],
        lib_dir:          project_dir + config[:lib],
        output_dir:       project_dir + config[:output],
        auto_extensions:  Array(config[:auto_extensions]),
        index_filenames:  Array(config[:index_filenames]),
        logger:,
      )
    end

    def build(use_existing_data: false)
      context.logger.log_timing("Building", "Build completed") do
        with_project_load_path do
          context.output_dir.mkdir unless context.output_dir.exist?

          ignore = make_ignore_filter

          if use_existing_data && @data
            context.logger.log("Using existing data")
          else
            read_data(ignore:)
          end

          context.logger.log_timing("Applying presentation", "Presentation applied") do
            Presentation::Builder.new(context:, ignore:)
              .build_clean(data: @data, output_dir: context.output_dir)
          end
        end
      end
    end

  private

    def read_data(ignore:)
      @data = if context.data_dir.exist?
        context.logger.log_timing("Reading data", "Read data") do
          data, file_count = Superfluous::Data.read(context:, ignore:)
          context.logger.log "Parsed #{file_count} data files"
          data
        end
      end
    end

    def with_project_load_path(&action)
      original_load_path = $LOAD_PATH.dup
      begin
        $LOAD_PATH.unshift(context.lib_dir) if context.lib_dir.exist?
        yield
      ensure
        $LOAD_PATH.replace(original_load_path)
      end
    end

    def make_ignore_filter
      gitignored = begin
        git_repo = Git.open(context.project_dir).lib
        git_repo.ignored_files.map { |path| Pathname.new(git_repo.git_work_dir) + path }
      rescue => e
        # Matching on an error message! Avert your innocent eyes, O reader
        raise unless e.message =~ /is not in a git working tree/
        []
      end

      lambda do |path|
        gitignored.include?(path)
      end
    end
  end

  # Shared by data and presentation builders
  def self.read_dir_scripts(dir, ignore:, parent_class: Object)
    dir_script_files = dir.children
      .filter { |f| is_dir_script?(f) }
      .reject { |f| ignore.call(f) }
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

  def self.is_dir_script?(pathname)
    pathname.basename.to_s =~ /^_.*\.rb$/
  end
end
