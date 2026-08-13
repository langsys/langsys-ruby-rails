# frozen_string_literal: true

require "spec_helper"
require "rails"
require "action_controller/railtie"
require "langsys/rails/railtie" # register the Railtie now that ::Rails::Railtie exists
require "rack/test"

APP_SETTINGS = {
  api_key: "test-key", project_id: "proj-1", api_url: "https://api.test/api",
  base_locale: "en-US", supported: %w[en-US es-ES]
}.freeze

class GreetingsController < ActionController::Base
  def show
    render plain: ls("Save", "UI")
  end
end

class LangsysTestApp < Rails::Application
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = "test-secret-key-base"
  config.logger = Logger.new(IO::NULL)
  config.hosts.clear
  APP_SETTINGS.each { |key, value| config.langsys.public_send("#{key}=", value) }
end

LangsysTestApp.initialize!
LangsysTestApp.routes.draw { get "/greet" => "greetings#show" }

RSpec.describe "Rails integration" do
  include Rack::Test::Methods

  def app
    LangsysTestApp
  end

  before do
    # The global after-hook resets module state, so re-apply the app's config each example
    # and back it with a fresh in-memory cache.
    configure_langsys(**APP_SETTINGS, cache: Langsys::Cache::Memory.new)
    stub_translations("es-ES", { "UI" => { "Save" => "Guardar" } })
    stub_translations("en-US", { "UI" => { "Save" => "Save" } })
  end

  it "translates via the ls helper using the ?locale= param and persists a cookie" do
    get "/greet?locale=es-ES"
    expect(last_response).to be_ok
    expect(last_response.body).to eq("Guardar")
    expect(last_response.headers["Set-Cookie"]).to include("langsys_locale=es-ES")
  end

  it "resolves the locale from Accept-Language without persisting a cookie" do
    get "/greet", {}, { "HTTP_ACCEPT_LANGUAGE" => "es-ES,en;q=0.5" }
    expect(last_response.body).to eq("Guardar")
    expect(last_response.headers["Set-Cookie"]).to be_nil
  end

  it "falls back to the base locale with no signal" do
    get "/greet"
    expect(last_response.body).to eq("Save")
  end
end
