# frozen_string_literal: true

require "langsys/rails"
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |c| c.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Reset all wrapper module state + the request-scoped locale between examples.
  config.after do
    Langsys::Rails::CurrentLocale.reset
    Langsys::Rails.reset_client!
    Langsys::Rails.instance_variable_set(:@config, nil)
    Langsys::Rails.instance_variable_set(:@resolver, nil)
  end
end

TRANSLATIONS_URL = "https://api.test/api/translations"
AUTHORIZE_URL = "https://api.test/api/authorize-project/proj-1"

def configure_langsys(**overrides)
  Langsys::Rails.configure do |config|
    config.api_key = "test-key"
    config.project_id = "proj-1"
    config.api_url = "https://api.test/api"
    config.base_locale = "en-US"
    config.cache = Langsys::Cache::Memory.new
    overrides.each { |key, value| config.public_send("#{key}=", value) }
  end
end

def catalog_body(data)
  { "status" => true, "words" => 0, "untranslatedWords" => 0, "data" => data }
end

def authorize_body(key_type: "read")
  {
    "status" => true,
    "data" => {
      "id" => "proj-1", "title" => "Test", "base_locale" => "en-us",
      "target_locales" => [], "default_locales" => {}, "key_type" => key_type,
      "langsys_settings" => { "translatable_items" => { "batch_limit" => 200 } }
    }
  }
end

def stub_translations(locale, data)
  stub_request(:get, TRANSLATIONS_URL)
    .with(query: { "project_id" => "proj-1", "locale" => locale, "format" => "flat" })
    .to_return(status: 200, body: JSON.generate(catalog_body(data)),
               headers: { "Content-Type" => "application/json" })
end

def stub_authorize(key_type: "read")
  stub_request(:get, AUTHORIZE_URL)
    .to_return(status: 200, body: JSON.generate(authorize_body(key_type: key_type)),
               headers: { "Content-Type" => "application/json" })
end
