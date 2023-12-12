guard :minitest do
  %w(test/ lib/ Gemfile.lock).each do |child|
    # Just rerun everything when anything changes
    watch(/^#{child}/) do |m|
      "test/" unless m[0].include?(".sass-cache")
    end
  end
end
