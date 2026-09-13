# frozen_string_literal: true

require "spec_helper"
require "support/test_app"

RSpec.describe "Rails integration" do
  include Rack::Test::Methods

  def app
    LangsysTestApp
  end

  before do
    configure_langsys(**APP_SETTINGS)
    stub_translations("es-es", { "UI" => { "Save" => "Guardar" } })
    stub_translations("en-us", { "UI" => { "Save" => "Save" } })
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
