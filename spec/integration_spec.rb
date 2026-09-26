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
    expect(last_response.headers["Set-Cookie"]).to include("langsys_locale=es-es")
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

  describe "SRV-6 — the locale the app resolved" do
    def vary = last_response.headers["Vary"]

    it "serves the app's locale whatever the URL, cookie and header say, and adds no Vary or cookie" do
      set_cookie "langsys_locale=de-de"
      get "/app_locale?app_locale=es-ES&locale=de-DE", {}, { "HTTP_ACCEPT_LANGUAGE" => "de-DE" }
      expect(last_response.body).to eq("Guardar")
      expect(vary.to_s).not_to match(/cookie|accept-language/i)
      expect(last_response.headers["Set-Cookie"]).to be_nil
    end

    it "maps a bare language to the project's default locale for it" do
      get "/app_locale?app_locale=es"
      expect(last_response.body).to eq("Guardar")
    end

    it "serves the base locale for an app locale the project does not serve" do
      get "/app_locale?app_locale=fr"
      expect(last_response.body).to eq("Save")
    end

    it "resolves the locale itself when the app set none" do
      get "/app_locale?locale=es-ES"
      expect(last_response.body).to eq("Guardar")
    end
  end

  describe "SRV-6 — one URL, four requests" do
    def vary = last_response.headers["Vary"]
    def cookie_written = last_response.headers["Set-Cookie"]

    it "lets the URL win over a conflicting cookie and header, and adds no Vary" do
      set_cookie "langsys_locale=de-de"
      get "/greet?locale=es-ES", {}, { "HTTP_ACCEPT_LANGUAGE" => "de-DE" }
      expect(last_response.body).to eq("Guardar")
      expect(vary.to_s).not_to match(/cookie|accept-language/i)
    end

    it "lets the cookie win over the header, with Vary: Cookie" do
      set_cookie "langsys_locale=es-es"
      get "/greet", {}, { "HTTP_ACCEPT_LANGUAGE" => "de-DE" }
      expect(last_response.body).to eq("Guardar")
      expect(vary).to match(/\bCookie\b/)
      expect(cookie_written).to be_nil
    end

    it "negotiates the header alone, with Vary: Accept-Language" do
      get "/greet", {}, { "HTTP_ACCEPT_LANGUAGE" => "es-ES,en;q=0.5" }
      expect(last_response.body).to eq("Guardar")
      expect(vary).to match(/\bAccept-Language\b/)
    end

    it "falls through an unsupported cookie to the header, and does not re-set the cookie" do
      set_cookie "langsys_locale=zz-zz"
      get "/greet", {}, { "HTTP_ACCEPT_LANGUAGE" => "es-ES" }
      expect(last_response.body).to eq("Guardar")
      expect(cookie_written).to be_nil
    end

    it "never serves or persists an unsupported URL locale" do
      get "/greet?locale=%3Cscript%3E"
      expect(last_response.body).to eq("Save")
      expect(cookie_written).to be_nil
    end

    it "keeps a Vary the application set, adding only what is missing" do
      get "/vary?locale=", {}, { "HTTP_ACCEPT_LANGUAGE" => "es-ES" }
      expect(vary.split(/,\s*/)).to eq(%w[Origin Accept-Language])
    end
  end
end
