module AssetHandler
  def self.for(path)
    if path.extname == ".rb"
      AssetHandler::Script.new(path)
    elsif tilt_template_class = ::Tilt.template_for(path)
      AssetHandler::Tilt.new(tilt_template_class, path)
    else
      AssetHandler::PassThrough.new(path)
    end
  end

  class Base
    attr_reader :setup

    def strip_ext?
      true
    end
  end

  class Tilt < AssetHandler::Base
    def initialize(template_class, path)
      @setup, content = AssetHandler.parse_setup(path)
      @template = template_class.new(path) { content }
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
      @setup = path.read  # The entire file is the setup; it returns the content
    end

    def render(scope:, props:, nested_content:)
      props[:content] or raise "Script #{@path} must return/yield a hash with a `content` key"
    end
  end

  class PassThrough < AssetHandler::Base
    def initialize(path)
      @setup = AssetHandler.read_setup_file(path)
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

  def self.parse_setup(path)
    setup_from_file = read_setup_file(path)
    embedded_setup, content = extract_embedded_setup(path)

    if setup_from_file && embedded_setup
      # TODO: support nested setups?
      raise "#{path} cannot have both embedded setup and setup from a file"
    end

    [
      setup_from_file || embedded_setup,
      content
    ]
  end

  def self.read_setup_file(path)
    # TODO: support dir-level shared setup?
    stripped_path = path
    while stripped_path.extname != ""
      stripped_path = stripped_path.sub_ext("")
    end
    setup_file = stripped_path.sub_ext("-setup.rb")
    setup_file.read if setup_file.exist?
  end

  def self.extract_embedded_setup(path)
    raw_content = path.read
    if raw_content =~ /\A\s*--- *\n(.*?)^ *--- *\n(.*)\Z/m
      [$1, $2]
    else
      [nil, raw_content]
    end
  end
end
