require_relative 'data'
require_relative 'site'
require_relative 'logging'
require 'awesome_print'

log_timing("Building", "Build completed") do
  project_dir = Pathname.new(ARGV[0])
  src_dir = project_dir + "src"

  data = log_timing("Reading data", "Read data") do
    read_data(src_dir + "data")
  end

  log
  log "──────────────────────── Data ────────────────────────"
  log_indented do
    log data.ai(indent: -2, ruby19_syntax: true)
  end
  log "──────────────────────────────────────────────────────"
  log

  log_timing("Processing site", "Processed site") do
    process_site(
      site_dir: src_dir + "site",
      data: data,
      output_dir: project_dir + "output")
  end
end
