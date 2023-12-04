require_relative "data"
require_relative "site"
require 'awesome_print'

project_dir = Pathname.new(ARGV[0])
src_dir = project_dir + "src"

data = read_data(src_dir + "data")

puts
puts "──────────────────────── Data ────────────────────────"
puts
ap data, indent: -2, ruby19_syntax: true
puts
puts "──────────────────────────────────────────────────────"
puts

process_site(
  site_dir: src_dir + "site",
  data: data,
  output_dir: project_dir + "output")
