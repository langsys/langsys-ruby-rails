# frozen_string_literal: true

require "uri"
require "langsys/rails"
require "webmock/rspec"

# Unit specs never touch the network. Live specs (tag :integration) hit a real Langsys
# backend, so the host of LANGSYS_API_URL is let past WebMock as well: `allow_localhost`
# does not count a Valet `.test` domain as localhost, and without this the live suite fails
# at the socket layer in a way that reads exactly like a credentials problem.
LIVE_HOST = begin
  url = ENV.fetch("LANGSYS_API_URL", nil)
  url.nil? || url.empty? ? nil : URI(url).host
end
WebMock.disable_net_connect!(allow_localhost: true, allow: [LIVE_HOST].compact)

LANGSYS_ENV = %w[LANGSYS_API_KEY LANGSYS_PROJECT_ID LANGSYS_API_URL LANGSYS_BASE_LOCALE LANGSYS_CACHE_TTL].freeze

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |c| c.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Unit specs are hermetic: credentials in the environment would silently fill any gap a
  # spec leaves in its configuration. Live specs keep them.
  config.around do |example|
    saved = LANGSYS_ENV.to_h { |key| [key, ENV.fetch(key, nil)] }
    LANGSYS_ENV.each { |key| ENV.delete(key) } unless example.metadata[:integration]
    example.run
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV.store(key, value) }
  end

  # Reset all wrapper module state + the request-scoped locale between examples.
  config.after do
    Langsys::Rails::CurrentLocale.reset
    Langsys::Rails.reset_client!
    Langsys::Rails.instance_variable_set(:@config, nil)
  end
end

API_URL = "https://api.test/api"
TRANSLATIONS_URL = "#{API_URL}/translations".freeze
AUTHORIZE_URL = "#{API_URL}/authorize-project/proj-1".freeze
REGISTRATION_URL = "#{API_URL}/translatable-items".freeze

def configure_langsys(**overrides)
  Langsys::Rails.configure do |config|
    config.api_key = "test-key"
    config.project_id = "proj-1"
    config.api_url = API_URL
    config.base_locale = "en-US"
    config.cache = Langsys::Cache::Memory.new
    overrides.each { |key, value| config.public_send("#{key}=", value) }
  end
end

def catalog_body(data, write_enabled: nil)
  body = { "status" => true, "words" => 0, "untranslatedWords" => 0, "data" => data }
  body["write_enabled"] = write_enabled unless write_enabled.nil?
  body
end

def authorize_body(key_type:, write_enabled:, target_locales: %w[es-es de-de])
  {
    "status" => true,
    "data" => {
      "id" => "proj-1", "title" => "Test", "base_locale" => "en-us",
      "target_locales" => target_locales, "default_locales" => {}, "key_type" => key_type,
      "write_enabled" => write_enabled,
      "langsys_settings" => { "translatable_items" => { "batch_limit" => 200 } }
    }
  }
end

def json_response(body)
  { status: 200, body: JSON.generate(body), headers: { "Content-Type" => "application/json" } }
end

# Locales are given in their wire form, lowercase (WIRE-3): the core normalises before it
# sends, so a stub keyed on the display form `es-ES` matches no request at all.
def stub_translations(locale, data, write_enabled: nil)
  stub_request(:get, TRANSLATIONS_URL)
    .with(query: { "project_id" => "proj-1", "locale" => locale, "format" => "flat" })
    .to_return(json_response(catalog_body(data, write_enabled: write_enabled)))
end

def stub_authorize(key_type: "write", write_enabled: true, **rest)
  stub_request(:get, AUTHORIZE_URL)
    .to_return(json_response(authorize_body(key_type: key_type, write_enabled: write_enabled, **rest)))
end

def stub_registration
  stub_request(:post, REGISTRATION_URL).to_return(json_response({ "status" => true, "data" => [] }))
end
