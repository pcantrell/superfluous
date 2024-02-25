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

    :ignore_patterns,
    :auto_extensions,
    :index_filenames,

    :logger,
  ) do
    def ignored?(relative_path)
      ignore_patterns.any? do |pat|
        File.fnmatch(pat, relative_path, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
      end
    end
  end

  DEFAULT_CONFIG = {
    data:         "src/data",
    presentation: "src/presentation",
    lib:          "src/lib",
    output:       "output",

    ignore: [],
    auto_extensions: %w[html],
    index_filenames: %w[index.html],
  }

  class Project
    attr_reader :project_dir, :data, :context

    def initialize(project_dir:, logger:, **config)
      project_dir = Pathname.new(project_dir)

      config = DEFAULT_CONFIG
        .merge(read_project_config(project_dir))
        .merge(config)

      @context = ProjectContext.new(
        project_dir:,
        data_dir:         project_dir + config[:data],
        presentation_dir: project_dir + config[:presentation],
        lib_dir:          project_dir + config[:lib],
        output_dir:       project_dir + config[:output],
        auto_extensions:  Array(config[:auto_extensions]),
        index_filenames:  Array(config[:index_filenames]),

        ignore_patterns: config[:ignore]
          .map do |pat|
            if pat.include?("/")
              pat.remove_prefix("/").remove_suffix("/")
            else
              "**/" + pat
            end
          end,

        logger:,
      )
    end

    def build(use_existing_data: false)
      context.logger.log_timing("Building", "Build completed") do
        with_project_load_path do
          context.output_dir.mkdir unless context.output_dir.exist?

          if use_existing_data && @data
            context.logger.log("Using existing data")
          else
            read_data
          end

          context.logger.log_timing("Applying presentation", "Presentation applied") do
            Presentation::Builder.new(context:)
              .build_clean(data: @data, output_dir: context.output_dir)
          end
        end
      end
    end

  private

    def read_project_config(project_dir)
      config_file = project_dir + "superfluous.json"
      if config_file.exist?
        JSON.parse(config_file.read, symbolize_names: true)
      else
        { }
      end
    end

    def read_data
      @data = if context.data_dir.exist?
        context.logger.log_timing("Reading data", "Read data") do
          data, file_count = Superfluous::Data.read(context:)
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
  end

  # Shared by data and presentation builders
  def self.read_dir_scripts(dir, context:, parent_class: Object)
    dir_script_files = dir.children
      .filter { |f| is_dir_script?(f) }
      .reject { |f| context.ignored?(f) }
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
