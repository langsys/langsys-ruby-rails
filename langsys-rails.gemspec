# frozen_string_literal: true

require_relative "lib/langsys/rails/version"

Gem::Specification.new do |spec|
  spec.name = "langsys-rails"
  spec.version = Langsys::Rails::VERSION
  spec.authors = ["Langsys"]
  spec.email = ["support@langsys.dev"]

  spec.summary = "Rails integration for Langsys — realtime, continuous translations."
  spec.description = <<~DESC
    A thin Rails wrapper over the `langsys` base gem. Adds a per-request locale (backed by
    ActiveSupport::CurrentAttributes), a controller concern that resolves the locale from the
    query string / cookie / Accept-Language header, an `ls` view helper, and a Railtie that
    wires it all up. All translation is delegated to the base SDK.
  DESC
  spec.homepage = "https://github.com/langsys/langsys-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "lib/tasks/*.rake", "sig/**/*.rbs", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 6.1"
  spec.add_dependency "activemodel", ">= 6.1"
  spec.add_dependency "activesupport", ">= 6.1"
  spec.add_dependency "langsys", ">= 0.1.0"
  spec.add_dependency "railties", ">= 6.1"
end
