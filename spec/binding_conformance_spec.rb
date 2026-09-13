# frozen_string_literal: true

require "spec_helper"
require "support/test_app"

# The binding rules (BIND-1..6), and the rules whose binding half is in-process: GATE-7's
# entry points and SRV-2's isolation. The hermetic twins of the live OBS-1, WIRE-4 and
# WIRE-5 examples are here too, for the mutation manifest.
RSpec.describe "Binding conformance" do
  include Rack::Test::Methods
  include RackHelpers

  def app
    LangsysTestApp
  end

  let(:client) { Langsys::Rails.client }
  let(:core_lib) { File.join(Gem.loaded_specs.fetch("langsys").full_gem_path, "lib") }

  before { configure_langsys(**APP_SETTINGS) }

  describe "BIND-1 — shape and timing only, never meaning" do
    let(:plural) { "You have {n, plural, one {# item} other {# items}}." }
    let(:catalog) do
      { "UI" => { "Save" => "Guardar", "Welcome, {name}" => "Bienvenido, {name}" },
        "Cart" => { plural => "Tienes {n, plural, one {# artículo} other {# artículos}}." } }
    end
    let(:vectors) do
      [["Save", "UI", {}], ["Not in the catalog", "UI", {}], ["Hello, {name}!", nil, { name: "Sarah" }],
       ["Hello, %name%!", "UI", { name: "Sarah" }], [plural, "Cart", { n: 3 }], [plural, "Cart", {}],
       [plural, "Cart", { n: nil }], ["Welcome, {name}", "UI", { name: nil }]]
    end

    before do
      stub_translations("es-es", catalog)
      Langsys::Rails::CurrentLocale.locale = "es-ES"
    end

    it "renders and queues exactly what calling the core directly does" do
      direct = Langsys::Client.new(api_key: "test-key", project_id: "proj-1", api_url: API_URL,
                                   base_locale: "en-US", locale: "es-ES", cache: Langsys::Cache::Memory.new)
      vectors.each do |phrase, category, params|
        expect(Langsys::Rails.t(phrase, category, **params))
          .to eq(direct.translate(phrase, category: category, params: params)),
              "diverged from the core on #{phrase.inspect} with #{params.inspect}"
      end
      expect(client.pending_phrases).to eq(direct.pending_phrases)
    end

    it "makes the ls helper the same call as Langsys::Rails.t" do
      helper = Object.new.extend(Langsys::Rails::Helper)
      vectors.each do |phrase, category, params|
        expect(helper.ls(phrase, category, **params)).to eq(Langsys::Rails.t(phrase, category, **params))
      end
    end
  end

  describe "BIND-4 — configuration (partial: three settings pending the ambient-locale ruling)" do
    let(:core_keywords) do
      Langsys::Client.instance_method(:initialize).parameters.filter_map do |kind, name|
        name if %i[key keyreq].include?(kind)
      end
    end
    let(:declared) { Langsys::Rails::Config::CORE_SETTINGS + Langsys::Rails::Config::LOCALE_SETTINGS }

    def capture_client_kwargs
      received = nil
      allow(Langsys::Client).to receive(:new).and_wrap_original do |original, **kwargs|
        received = kwargs
        original.call(**kwargs)
      end
      Langsys::Rails.client
      received
    end

    it "names every core setting by the core client's own keyword" do
      expect(Langsys::Rails::Config::CORE_SETTINGS - core_keywords).to be_empty
    end

    it "hands each configured core setting to the core client unchanged" do
      sentinels = { api_key: "k", project_id: "p", api_url: "https://sentinel.test/api", base_locale: "fr-FR",
                    cache: Langsys::Cache::Memory.new, cache_ttl: 7, timeout: 1.5, auto_flush: false,
                    logger: Logger.new(IO::NULL) }
      configure_langsys(**sentinels)
      expect(capture_client_kwargs.slice(*sentinels.keys)).to eq(sentinels)
    end

    it "gives auto_flush the core's meaning and the core's default" do
      core_default = File.read(File.join(core_lib, "langsys/client.rb"))[/auto_flush: (true|false)/, 1]
      expect(core_default).not_to be_nil
      expect(Langsys::Rails::Config.new.auto_flush.to_s).to eq(core_default)
      configure_langsys(auto_flush: false)
      expect(capture_client_kwargs.fetch(:auto_flush)).to be(false)
    end

    it "maps `supported` to the core's own locale-negotiation parameter" do
      expect(Langsys::Client.instance_method(:detect_preferred_locale).parameters.map(&:last)).to include(:supported)
    end

    it "introduces exactly three settings the core has no equivalent for" do
      expect(Langsys::Rails::Config::LOCALE_SETTINGS - %i[supported])
        .to contain_exactly(:query_param, :cookie_name, :cookie_max_age)
    end

    it "accepts only declared settings, and the Railtie reads exactly those" do
      setters = Langsys::Rails::Config.public_instance_methods(false).grep(/\A\w+=\z/).map { |m| m.to_s.chomp("=").to_sym }
      expect(setters).to match_array(declared)
      expect(Langsys::Rails::Railtie::SETTINGS).to match_array(declared)
    end
  end

  describe "BIND-5 — no cached lookup results" do
    it "shows a changed catalog on the very next call" do
      Langsys::Rails::CurrentLocale.locale = "es-ES"
      stub_translations("es-es", { "UI" => { "Save" => "Guardar" } })
      expect(Langsys::Rails.t("Save", "UI")).to eq("Guardar")

      client.clear_cache
      WebMock.reset!
      stub_translations("es-es", { "UI" => { "Save" => "Salvar" } })
      expect(Langsys::Rails.t("Save", "UI")).to eq("Salvar")
    end

    it "memoizes nothing but its own configuration objects" do
      memos = Dir.glob(File.expand_path("../lib/**/*.rb", __dir__)).flat_map do |path|
        File.read(path).scan(/@(\w+)\s*\|\|=/).flatten
      end
      expect(memos).to contain_exactly("config", "resolver", "client")
    end
  end

  describe "BIND-6 — the narrowest surface" do
    it "exposes the core client by reference plus framework idioms, and no behaviour of its own" do
      expect(Langsys::Rails.singleton_methods(false))
        .to contain_exactly(:configure, :config, :resolver, :client, :client=, :reset_client!, :t, :locale)
      expect(client).to be_a(Langsys::Client)
      expect(Langsys::Rails.client).to equal(client)
      expect(Langsys::Rails::Helper.public_instance_methods(false)).to eq([:ls])
    end
  end

  describe "GATE-7 — every binding path that can detect a miss feeds the core's register lane" do
    before do
      # A read-only session: the boundary's flush then retains the queue, so it stays inspectable.
      stub_authorize(key_type: "read", write_enabled: false)
      stub_translations("en-us", { "UI" => { "Save" => "Save" } })
    end

    it "Langsys::Rails.t queues a miss, once, and a hit not at all" do
      2.times { Langsys::Rails.t("Missing via t", "UI") }
      Langsys::Rails.t("Save", "UI")
      expect(client.pending_phrases).to eq([{ "phrase" => "Missing via t", "category" => "UI" }])
    end

    it "the ls helper in a rendered view queues a miss, once, and a hit not at all" do
      RenderPlan.phrases = [["Missing via ls", "UI"], ["Missing via ls", "UI"], ["Save", "UI"]]
      get "/plan"
      expect(client.pending_phrases).to eq([{ "phrase" => "Missing via ls", "category" => "UI" }])
    end
  end

  describe "SRV-2 — concurrent requests do not observe each other's locale" do
    it "serves each of two renders suspended mid-flight together only its own locale's text" do
      stub_translations("es-es", { "UI" => { "Save" => "Guardar", "Cancel" => "Cancelar" } })
      stub_translations("de-de", { "UI" => { "Save" => "Speichern", "Cancel" => "Abbrechen" } })
      client # built once, before the threads race to build it
      rendezvous = ConcurrentController.rendezvous = Rendezvous.new(parties: 2)
      bodies = {}
      lock = Mutex.new

      threads = %w[es-ES de-DE].map do |locale|
        Thread.new do
          _, _, _, body = call_app("/concurrent?locale=#{locale}")
          text = read_body(body)
          body.close
          lock.synchronize { bodies[locale] = text }
        end
      end
      threads.each { |thread| thread.join(10) }

      expect(rendezvous.met?).to be(true)
      expect(bodies).to eq("es-ES" => "Guardar|Cancelar", "de-DE" => "Speichern|Abbrechen")
    end
  end

  describe "OBS-1 — the core's diagnostics reach the Rails log" do
    it "logs the once-per-process unusable-capability warning to Rails.logger when none is configured" do
      io = StringIO.new
      original = ::Rails.logger
      ::Rails.logger = Logger.new(io)
      stub_authorize(key_type: "read", write_enabled: false)
      stub_translations("en-us", { "UI" => {} })
      3.times do |i|
        RenderPlan.phrases = [["Unregistrable #{i}", "UI"]]
        get "/plan"
      end
      expect(io.string.scan("not write-enabled").size).to eq(1)
    ensure
      ::Rails.logger = original
    end
  end

  describe "WIRE-4 — an unreachable API does not turn the page into an error" do
    it "serves the source language and records nothing" do
      stub_request(:get, TRANSLATIONS_URL).with(query: hash_including({})).to_raise(Errno::ECONNREFUSED)
      get "/greet?locale=es-ES"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("Save")
      expect(client.has_pending?).to be(false)
    end
  end

  describe "WIRE-5 — the API base can be redirected after first use" do
    def stub_base(base, text)
      stub_request(:get, "#{base}/translations")
        .with(query: hash_including("locale" => "es-es"))
        .to_return(json_response(catalog_body({ "UI" => { "Save" => text } })))
    end

    it "sends the next request's lookups to the new base" do
      stub_base("https://first.test/api", "Guardar (first)")
      stub_base("https://second.test/api", "Guardar (second)")

      configure_langsys(**APP_SETTINGS, api_url: "https://first.test/api")
      get "/greet?locale=es-ES"
      expect(last_response.body).to eq("Guardar (first)")

      Langsys::Rails.configure do |config|
        config.api_url = "https://second.test/api"
        config.cache = Langsys::Cache::Memory.new
      end
      get "/greet?locale=es-ES"
      expect(last_response.body).to eq("Guardar (second)")
    end
  end
end
