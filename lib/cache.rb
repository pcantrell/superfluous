require 'cgi'

module Superfluous
  class Cache
    def initialize(project_context)
      @project_context = project_context
    end

    def get(key:, &block)
      logger.log_indented do
        script_path =
          Pathname.new(caller_locations(4, 1)[0].path)
            .relative_path_from(@project_context.project_dir)
        cache_file_path =
          @project_context.cache_dir +
            script_path.to_s.gsub("/", "_") +
            key.map { |part| CGI.escape(part.to_s) }.join("/")

        unless cache_file_path.exist?
          logger.make_last_temporary_permanent
          logger.log_timing(
            "Generating cache content for #{script_path} #{key.inspect}",
            "Generated cache content"
          ) do
            cache_file_path.parent.mkpath
            block.call(cache_file_path)

            unless cache_file_path.exist?
              raise "Cache callback failed to generate output file: #{cache_file_path}"
            end
            logger.log "Cache file created: #{cache_file_path}"
          end
        end

        cache_file_path
      end
    end

    def logger
      @project_context.logger
    end
  end
end
