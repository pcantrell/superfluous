guard :minitest do
  %w(test lib).each do |subdir|
    # Just rerun everything when anything changes
    watch(%r{^#{subdir}/}) { "test/" }
  end
end
