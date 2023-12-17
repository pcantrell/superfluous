require 'strscan'

module AssetHandler
  class Cache
    def initialize
      @handler_cache = {}
    end

    def for(path)
      # TODO: handle *+script.rb with no corresponding script
      return nil if path.basename.to_s.end_with?(SCRIPT_FILE_SUFFIX)

      @handler_cache[path] ||=
        if path.extname == ".superf"
          AssetHandler::SuperfluousFile.new(path)
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

  # Superfluous custom file format with fenced sections
  #
  class SuperfluousFile < AssetHandler::Base
    def initialize(path)
      @path = path
      parse_sections(path.read) do |name, type, content|
        case name
          when 'script'
            set_script(type, content)
          when 'template'
            set_template(type, content)
          when 'style'
            unless template_class = ::Tilt.template_for(type)
              raise "Unknown template type #{type.inspect} in .superf file"
            end
            puts AssetHandler::Tilt.new(template_class, @path, content).render(scope: nil, props: nil)
          else
            raise "Unknown fence: #{name.inspect}"
        end
      end
    end

    def render(scope:, props:, nested_content:)
      if @template_handler
        @template_handler.render(scope:, props:, nested_content:)
      else
        props[:content] or raise "Script with no template at #{@path} must return/yield a hash with a `content` key"
      end
    end

  private

    def parse_sections(content, &block)
      scanner = StringScanner.new(content)
      
      before_first = scanner.scan_until(NEXT_FENCE)
      unless before_first.blank?
        raise "Illegal content before first fence in .superf file: #{before_first.inspect}"
      end

      until scanner.eos?
        scanner.scan(FENCE) or raise "Malformed fence at #{scanner.charpos}"
        yield(scanner[:name], scanner[:type], scanner.scan_until(NEXT_FENCE))
      end
    end

    FENCE_BAR = /\s*[-–]{3,}\s*/
    NEXT_FENCE = /^ (?=#{FENCE_BAR}) | \z /x
    FENCE = /^ #{FENCE_BAR} (?<name>.+)\.(?<type>.+?) #{FENCE_BAR} $/x

    def set_script(type, content)
      raise "Unknown script type #{type.inspect} in .superf file" unless type == "rb"
      raise ".superf file contains multiple script sections" if @script
      @script = content
    end

    def set_template(type, content)
      unless template_class = ::Tilt.template_for(type)
        raise "Unknown template type #{type.inspect} in .superf file"
      end
      raise ".superf file contains multiple template sections" if @template_handler
      @template_handler = AssetHandler::Tilt.new(template_class, @path, content)
    end
  end

  # Tilt handles template files: Haml, Erb, Sass, etc.
  #
  class Tilt < AssetHandler::Base
    def initialize(template_class, path, content = nil)
      @script = AssetHandler.read_script_file(path)
      @template_path = path
      @template_dir = path.parent
      content ||= path.read
      Dir.chdir(@template_dir) do  # for relative includes (e.g. sass) embedded in template
        @template = template_class.new(path) { content }
      end
    end

    def render(scope:, props:, nested_content: nil)
      @template.render(scope, props) do
        if nested_content.nil?
          raise "Template called yield, but no nested content given"
        end
        nested_content.call.html_safe
      end
    end
  end

  # Handler for unprocessed file types
  #
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

  SCRIPT_FILE_SUFFIX = "+script.rb"

  def self.read_script_file(path)
    # TODO: support dir-level shared setup/config/context script?
    stripped_path = path
    while stripped_path.extname != ""
      stripped_path = stripped_path.sub_ext("")
    end
    script_file = stripped_path.sub_ext(SCRIPT_FILE_SUFFIX)
    script_file.read if script_file.exist?
  end
end
