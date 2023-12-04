require_relative "data"
require_relative "pages"
require 'awesome_print'

site_dir = Pathname.new(ARGV[0])

data = read_data(site_dir + "data")

puts
puts "──────────────────────── Data ────────────────────────"
puts
ap data, indent: -2, ruby19_syntax: true
puts
puts "──────────────────────────────────────────────────────"
puts

process_pages(
  pages_dir: site_dir + "pages",
  data: data,
  output_dir: site_dir + "output")
