module AssetHandler
  class Cache
    def initialize
      @handler_cache = {}
    end

    def for(path)
      # TODO: handle *-script.rb with no corresponding script
      return nil if path.basename.to_s.end_with?(SCRIPT_FILE_SUFFIX)

      @handler_cache[path] ||=
        if path.extname == ".rb"
          AssetHandler::Script.new(path)
        elsif tilt_template_class = ::Tilt.template_for(path)
          AssetHandler::Tilt.new(tilt_template_class, path)
        else
          AssetHandler::PassThrough.new(path)
        end
    end
  end

  class Base
    attr_reader :script

    def strip_ext?
      true
    end
  end

  class Tilt < AssetHandler::Base
    def initialize(template_class, path)
      @script, content = AssetHandler.read_script(path)
      @template_path = path
      @template_dir = path.parent
      Dir.chdir(@template_dir) do  # for relative includes (e.g. sass) embedded in template
        @template = template_class.new(path) { content }
      end
    end

    def render(scope:, props:, nested_content:)
      @template.render(scope, props) do
        if nested_content.nil?
          raise "Template called yield, but no nested content given"
        end
        nested_content.call.html_safe
      end
    end
  end

  class Script < AssetHandler::Base
    def initialize(path)
      @path = path
      @script = path.read  # The entire file is the script; it returns the content
    end

    def render(scope:, props:, nested_content:)
      props[:content] or raise "Script #{@path} must return/yield a hash with a `content` key"
    end
  end

  class PassThrough < AssetHandler::Base
    def initialize(path)
      @script = AssetHandler.read_script_file(path)
      @content = path.read
    end

    def render(scope:, props:, nested_content:)
      @content
    end

    def strip_ext?
      false
    end
  end

private

  SCRIPT_FILE_SUFFIX = "-script.rb"

  def self.read_script(path)
    script_from_file = read_script_file(path)
    embedded_script, content = extract_embedded_script(path)

    if script_from_file && embedded_script
      raise "#{path} cannot have both embedded script and *-script file"
    end

    [
      script_from_file || embedded_script,
      content
    ]
  end

  def self.read_script_file(path)
    # TODO: support dir-level shared setup/config/context script?
    stripped_path = path
    while stripped_path.extname != ""
      stripped_path = stripped_path.sub_ext("")
    end
    script_file = stripped_path.sub_ext(SCRIPT_FILE_SUFFIX)
    script_file.read if script_file.exist?
  end

  def self.extract_embedded_script(path)
    raw_content = path.read
    if raw_content =~ /\A\s*--- *\n(.*?)^ *--- *\n(.*)\Z/m
      [$1, $2]
    else
      [nil, raw_content]
    end
  end
end


module SassOptionsOverride
  def sass_options
    @options[:cache_location] = Superfluous.work_dir("sass-cache").to_s
    super
  end
end

class ::Tilt::SassTemplate
  prepend SassOptionsOverride
end
