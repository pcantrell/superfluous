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
end
