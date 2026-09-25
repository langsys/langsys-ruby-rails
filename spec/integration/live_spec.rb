# frozen_string_literal: true

require "spec_helper"
require "securerandom"
require "support/test_app"

# Live evidence against a real Langsys backend: the rows graded `live` in CONFORMANCE.md.
# Graded evidence has to be re-runnable by whoever reads the row, so the probes are
# committed rather than described. Skipped unless credentials are in the environment:
#
#   LANGSYS_API_URL=http://langsys2.test/api \
#   LANGSYS_PROJECT_ID=c0de0000-5d10-4000-8000-000000000013 \
#   LANGSYS_API_KEY=sdk_integration_rails_local_only_do_not_deploy \
#   LANGSYS_READ_KEY=sdk_integration_rails_read_local_only_do_not_deploy \
#     bundle exec rake integration
#
# Those are the fixed, local-only credentials langsys2's SdkIntegrationSeeder creates for
# this repo (slot 13) — its own project, so what this suite registers never shows up in
# another lane's catalog. The seeder ships "Technical Support" (CAT_3) translated to es-es
# as "Soporte Técnico", base locale en-us, machine translation off.
#
# Assertions read SERVER STATE through a separate, uncached client (CONF-1): what the
# server holds, never what this binding sent.
LIVE_REQUIRED_ENV = %w[LANGSYS_API_URL LANGSYS_PROJECT_ID LANGSYS_API_KEY LANGSYS_READ_KEY].freeze

# The local backend throttles its API at 120 requests a minute per address, and every lane on
# this machine shares 127.0.0.1. A throttled lookup degrades to source text, which reads as a
# failed translation, so the suite paces itself to half that budget.
module LivePacing
  BUDGET = 60
  @sent = []

  class << self
    def record = @sent << Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def wait_for_budget
      loop do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @sent.reject! { |at| at < now - 60 }
        break if @sent.size < BUDGET

        sleep(@sent.first + 60 - now)
      end
    end
  end
end
WebMock.after_request(real_requests_only: true) { |_request, _response| LivePacing.record }

RSpec.describe "Rails binding, live", :integration do
  include Rack::Test::Methods
  include RackHelpers

  def app
    LangsysTestApp
  end

  before do
    missing = LIVE_REQUIRED_ENV.select { |name| ENV.fetch(name, "").empty? }
    skip "set #{missing.join(', ')} to run the live specs" unless missing.empty?
    LivePacing.wait_for_budget
  end

  let(:write_key) { ENV.fetch("LANGSYS_API_KEY") }
  let(:read_key) { ENV.fetch("LANGSYS_READ_KEY") }

  def configure_live(key:, **overrides)
    Langsys::Rails.configure do |config|
      config.api_key = key
      config.project_id = ENV.fetch("LANGSYS_PROJECT_ID")
      config.api_url = ENV.fetch("LANGSYS_API_URL")
      config.base_locale = "en-US"
      config.cache = Langsys::Cache::Memory.new
      overrides.each { |name, value| config.public_send("#{name}=", value) }
    end
  end

  def unique(label)
    "Rails live #{label} #{SecureRandom.hex(6)}"
  end

  def server_holds?(phrase, category = "CAT_3")
    reader = Langsys::Client.new(api_key: write_key, project_id: ENV.fetch("LANGSYS_PROJECT_ID"),
                                 api_url: ENV.fetch("LANGSYS_API_URL"), cache: Langsys::Cache::Memory.new)
    catalog = reader.get_translations(locale: "en-US", use_cache: false)
    raise "live catalog unavailable — is the stack up, or throttling (429)?" unless catalog.is_a?(Hash)

    catalog.fetch(category, {}).key?(phrase)
  end

  it "can tell a phrase the server holds from one it does not (verifier control)" do
    expect(server_holds?("Technical Support")).to be(true)
    expect(server_holds?(unique("never registered"))).to be(false)
  end

  describe "SRV-1" do
    it "serves the request locale's translation in the response bytes, and the base language only for a miss" do
      configure_live(key: write_key)
      miss = unique("SRV-1 control")
      RenderPlan.phrases = [["Technical Support", "CAT_3"], [miss, "CAT_3"]]

      get "/plan?locale=es-ES"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("Soporte Técnico\n#{miss}")
      expect(server_holds?(miss)).to be(true) # the miss was reported, and the server now holds it
    end
  end

  describe "SRV-3 / REG-3" do
    it "registers a render's miss only once the server closes the body" do
      configure_live(key: write_key)
      miss = unique("SRV-3 body-close")
      RenderPlan.phrases = [[miss, "CAT_3"]]

      _, status, _, body = call_app("/plan")
      expect(status).to eq(200)
      expect(server_holds?(miss)).to be(false)

      expect(read_body(body)).to eq(miss)
      expect(server_holds?(miss)).to be(false)

      body.close
      expect(server_holds?(miss)).to be(true)
    end

    it "registers a render's miss only once the server runs rack.response_finished" do
      configure_live(key: write_key)
      miss = unique("SRV-3 response-finished")
      RenderPlan.phrases = [[miss, "CAT_3"]]

      env, status, headers, body = call_app("/plan", "rack.response_finished" => [])
      read_body(body)
      body.close
      expect(server_holds?(miss)).to be(false)

      finish_response(env, status, headers)
      expect(server_holds?(miss)).to be(true)
    end

    it "holds a render's miss from another request's flush until its own response is sent" do
      configure_live(key: write_key)
      Langsys::Rails.client
      run = SecureRandom.hex(6)
      tag_a = "A-#{run}"
      tag_b = "B-#{run}"
      holding = Queue.new
      release = Queue.new
      EventsController.hold = lambda do |tag|
        next unless tag == tag_a

        holding << true
        release.pop
      end
      a = Thread.new do
        _, _, _, body = call_app("/events?tag=#{tag_a}")
        read_body(body)
        body.close
      end
      holding.pop
      get "/events?tag=#{tag_b}" # B completes and flushes while A is still rendering
      expect(server_holds?("Miss #{tag_b}", "UI")).to be(true) # positive control: B's flush ran
      expect(server_holds?("Miss #{tag_a}", "UI")).to be(false)
      release << true
      a.join(15)
      expect(server_holds?("Miss #{tag_a}", "UI")).to be(true)
    end

    it "pushes nothing from a read-only key, while the same render on a write key does" do
      miss = unique("SRV-3 read-only")
      RenderPlan.phrases = [[miss, "CAT_3"]]

      configure_live(key: read_key)
      get "/plan"
      expect(last_response.body).to eq(miss)
      expect(server_holds?(miss)).to be(false)

      configure_live(key: write_key) # positive control: the identical render, on a write key
      get "/plan"
      expect(server_holds?(miss)).to be(true)
    end
  end

  describe "SRV-6 — one URL, four requests, against the project's own locales" do
    before do
      configure_live(key: write_key)
      RenderPlan.phrases = [["Technical Support", "CAT_3"]]
    end

    def vary = last_response.headers["Vary"].to_s

    it "lets the URL win over a conflicting cookie and header, and adds no Vary" do
      set_cookie "langsys_locale=en-us"
      get "/plan?locale=es-ES", {}, { "HTTP_ACCEPT_LANGUAGE" => "en-US" }
      expect(last_response.body).to eq("Soporte Técnico")
      expect(vary).not_to match(/cookie|accept-language/i)
    end

    it "lets the cookie win over the header, with Vary: Cookie" do
      set_cookie "langsys_locale=es-es"
      get "/plan", {}, { "HTTP_ACCEPT_LANGUAGE" => "en-US" }
      expect(last_response.body).to eq("Soporte Técnico")
      expect(vary).to match(/\bCookie\b/)
    end

    it "negotiates the header alone, with Vary: Accept-Language" do
      get "/plan", {}, { "HTTP_ACCEPT_LANGUAGE" => "es-ES,en;q=0.5" }
      expect(last_response.body).to eq("Soporte Técnico")
      expect(vary).to match(/\bAccept-Language\b/)
    end

    it "falls through a locale the project does not serve, and never writes it back" do
      set_cookie "langsys_locale=fr-fr"
      get "/plan", {}, { "HTTP_ACCEPT_LANGUAGE" => "es-ES" }
      expect(last_response.body).to eq("Soporte Técnico")
      expect(last_response.headers["Set-Cookie"]).to be_nil
    end
  end

  describe "GATE-10 — the layout helper, against the project's base locale" do
    before { configure_live(key: write_key) }

    it "marks a page rendered in a target locale, and leaves a base-locale page unmarked" do
      get "/layout?locale=es-ES"
      expect(last_response.body).to start_with('<html data-ls-resolved="es-es">')
      get "/layout?locale=en-US"
      expect(last_response.body).to start_with("<html>")
    end
  end

  describe "MSG-6 / MSG-8 — a failed form's templates" do
    def with_label(label)
      I18n.backend.store_translations(:en, activemodel: { attributes: { signup: { email: label } } })
      yield
    ensure
      I18n.reload!
    end

    it "registers a template the catalog lacks under Errors, once the response is sent" do
      configure_live(key: write_key)
      label = "email #{SecureRandom.hex(4)}"
      template = "The #{label} is required."
      with_label(label) do
        env = Rack::MockRequest.env_for("/signups", method: "POST", params: { email: "" })
        status, _, body = LangsysTestApp.call(env)
        expect(status).to eq(422)
        expect(read_body(body).lines.first.chomp).to eq(template)
        expect(server_holds?(template, "Errors")).to be(false)
        body.close
      end
      expect(server_holds?(template, "Errors")).to be(true)
      expect(server_holds?(template, "CAT_3")).to be(false)
    end

    it "registers nothing from a read-only key, while the same failure on a write key does" do
      label = "email #{SecureRandom.hex(4)}"
      template = "The #{label} is required."
      with_label(label) do
        configure_live(key: read_key)
        post "/signups", email: ""
        expect(server_holds?(template, "Errors")).to be(false)
        configure_live(key: write_key)
        post "/signups", email: ""
      end
      expect(server_holds?(template, "Errors")).to be(true)
    end
  end

  describe "MSG-7 — the build-time listing registers, idempotently" do
    it "registers every listed template on the first run, and nothing on the second" do
      configure_live(key: write_key)
      label = "email #{SecureRandom.hex(4)}"
      I18n.backend.store_translations(:en, activemodel: { attributes: {
                                        signup: { email: label, age: "age", tags: "tags", starts_on: "start date",
                                                  password: "password" }
                                      } })
      run = lambda do
        out = StringIO.new
        status = Langsys::Messages::Command.run(sources: [Langsys::Rails::ValidatorSource.new([Signup])],
                                                client: Langsys::Rails.client, register: true, out: out)
        [status, out.string[/registered (\d+) new/, 1].to_i]
      end
      first_status, first = run.call
      expect(first_status).to eq(0)
      expect(first).to be_positive
      expect(server_holds?("The #{label} is required.", "Errors")).to be(true)
      configure_live(key: write_key) # a fresh client, with nothing cached from the first run
      expect(run.call).to eq([0, 0])
    ensure
      I18n.reload!
    end
  end

  describe "OBS-1" do
    around do |example|
      original = ::Rails.logger
      example.run
    ensure
      ::Rails.logger = original
    end

    it "puts the core's unusable-capability diagnostic in the Rails log, once across requests" do
      io = StringIO.new
      ::Rails.logger = Logger.new(io)
      configure_live(key: read_key)
      3.times do |i|
        RenderPlan.phrases = [[unique("OBS-1 #{i}"), "CAT_3"]]
        get "/plan"
      end
      expect(io.string.scan("not write-enabled").size).to eq(1)
    end

    it "logs no such diagnostic on a write key (control)" do
      io = StringIO.new
      ::Rails.logger = Logger.new(io)
      configure_live(key: write_key)
      RenderPlan.phrases = [[unique("OBS-1 control"), "CAT_3"]]
      get "/plan"
      expect(io.string).not_to include("not write-enabled")
    end
  end

  describe "WIRE-4" do
    it "serves the page in the source language when the API refuses the key, and records nothing" do
      configure_live(key: "not-a-real-key-#{SecureRandom.hex(4)}")
      RenderPlan.phrases = [["Technical Support", "CAT_3"]]

      get "/plan?locale=es-ES"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("Technical Support")
      expect(Langsys::Rails.client.has_pending?).to be(false)
    end
  end

  describe "WIRE-5" do
    it "takes a redirect made after first use: a dead address degrades, then the live one translates" do
      configure_live(key: write_key, api_url: "http://127.0.0.1:9/api")
      RenderPlan.phrases = [["Technical Support", "CAT_3"]]
      get "/plan?locale=es-ES"
      expect(last_response.body).to eq("Technical Support")

      Langsys::Rails.configure do |config|
        config.api_url = ENV.fetch("LANGSYS_API_URL")
        config.cache = Langsys::Cache::Memory.new
      end
      get "/plan?locale=es-ES"
      expect(last_response.body).to eq("Soporte Técnico")
    end
  end
end
