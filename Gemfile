# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :test do
  gem "guard", "~> 2.18"
  gem "guard-minitest", "~> 2.4"
  gem "diffy", "~> 3.4"
  gem "minitest-reporters", "~> 1.6"
  gem "minitest-focus", "~> 1.4"

  gem "haml", "~> 6.2"
  gem "sassc", "~> 2.4"
end

group :development do
  gem "pry", "~> 0.14.2"
  gem "rake", "~> 13.1"
end

# Clients will need this unless / until adsf merges manual reload PR:
# https://github.com/denisdefreyne/adsf/pull/42
gem "adsf", git: "https://github.com/pcantrell/adsf", branch: "manual-reload"
gem "adsf-live", git: "https://github.com/pcantrell/adsf", branch: "manual-reload"
