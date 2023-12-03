require_relative "data"
require_relative "pages"

site_dir = Pathname.new(ARGV[0])

data = read_data(site_dir + "data")

process_pages(
  pages_dir: site_dir + "pages",
  data: data,
  output_dir: site_dir + "output")
