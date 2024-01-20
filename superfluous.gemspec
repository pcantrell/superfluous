Gem::Specification.new do |s|
  s.name        = "superfluous"
  s.version     = "0.1"
  s.authors     = ['Paul Cantrell']
  s.summary     = 'Data-driven static site generator'
  s.email       = 'cantrell@pobox.com'
  s.files       = Dir['{lib,bin}/**/*'] + %w(README.md LICENSE)
  s.test_files  = Dir['{test}/**/*']
  s.homepage    = 'https://github.com/pcantrell/superfluous'
  s.metadata    = { "source_code_uri" => "https://github.com/pcantrell/superfluous" }
  s.license     = 'MIT'

  # Data parsing
  s.add_runtime_dependency "kramdown", "~> 2.4"

  # Templating
  s.add_runtime_dependency "tilt", "~> 2.3"

  # Util
  s.add_runtime_dependency "activesupport", "~> 7.1"
  s.add_runtime_dependency "awesome_print", "~> 1.9"
  s.add_runtime_dependency "ansi", "~> 1.5"

  # Server
  s.add_runtime_dependency "adsf", "~> 1.5"
  s.add_runtime_dependency "adsf-live", "~> 1.5"
end
