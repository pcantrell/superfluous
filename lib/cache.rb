require 'cgi'

module Superfluous
  class Cache
    def initialize(project_context)
      @project_context = project_context
    end

    def get(key:, &block)
      logger.log_indented do
        # Brittle code: we look 4 frames back in caller_locations here because the stack is:
        #
        #   1. logger.log_indented (this block)
        #   2. get (this method)
        #   3. cached_* in CacheAccess
        #   4. <<caller>>
        #
        # Refactoring code in this file may require that 4 to change to a different number.
        calling_script_stack_depth = 4

        script_path =
          Pathname.new(caller_locations(calling_script_stack_depth, 1)[0].path)
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

  module CacheAccess
    def cached_file(**opts, &block)
      @cache.get(**opts, &block)
    end
    
    def cached_content(**opts, &block)
      File.read(
        @cache.get(**opts) do |outfile|
          File.write(outfile, block.call)
        end
      )
    end
  end
end
