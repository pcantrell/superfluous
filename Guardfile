guard :minitest do
  %w[test/ lib/ Gemfile.lock].each do |child|
    # Just rerun everything when anything changes
    watch(/^#{child}/) do |m|
      "test/"
    end
  end
end
