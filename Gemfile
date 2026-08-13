# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Local co-development: the base gem isn't published to RubyGems yet. The gemspec keeps the
# canonical `langsys >= 0.1.0` range; remove this line once it's published.
gem "langsys", path: "../langsys-ruby"

group :development, :test do
  # Ruby 3.0 ships psych 3.3 as a default gem; newer psych needs libyaml headers to compile.
  gem "psych", "~> 3.3"
  gem "rake", "~> 13.0"
  gem "rbs", "~> 3.4" # validates the type signatures in sig/
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.60", require: false
  gem "webmock", "~> 3.19"
end
