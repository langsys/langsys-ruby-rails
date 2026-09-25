# frozen_string_literal: true

require "spec_helper"
require "support/test_app"

# The request boundary: the two obligations the base SDK's CONFORMANCE.md hands to this
# wrapper — dropping the write decision per request (GATE-3) and flushing discovered phrases
# before the request's context ends (REG-3) — plus the timing SRV-3 puts on that flush.
#
# These are the hermetic twins of spec/integration/live_spec.rb. The live file carries the
# graded evidence for the properties that depend on what the API answers; these pin the
# binding's own sequencing without a backend, and are what the mutation manifest reddens.
RSpec.describe Langsys::Rails::RequestBoundary do
  include Rack::Test::Methods
  include RackHelpers

  def app
    LangsysTestApp
  end

  let(:client) { Langsys::Rails.client }

  before { configure_langsys(**APP_SETTINGS) }

  it "sits in front of ActionDispatch::Executor" do
    stack = LangsysTestApp.middleware.map(&:klass)
    expect(stack).to include(described_class, ActionDispatch::Executor)
    expect(stack.index(described_class)).to be < stack.index(ActionDispatch::Executor)
  end

  it "neither builds a client nor raises for a request that never translated" do
    Langsys::Rails.instance_variable_set(:@config, nil) # no credentials: building a client would raise
    get "/health"
    expect(last_response.status).to eq(200)
    expect(Langsys::Rails.send(:built_client)).to be_nil
  end

  describe "SRV-3 / REG-3 — the flush runs after the response is sent" do
    before do
      stub_authorize(key_type: "write", write_enabled: true)
      stub_translations("en-us", { "UI" => {} })
      stub_registration
      RenderPlan.phrases = [["Brand new", "UI"]]
    end

    it "on the body-close path, registers nothing until the server closes the body" do
      _, status, _, body = call_app("/plan")
      expect(status).to eq(200)
      expect(client.registered?("UI", "Brand new")).to be(false)
      expect(client.has_pending?).to be(true)

      expect(read_body(body)).to eq("Brand new")
      expect(client.registered?("UI", "Brand new")).to be(false)

      body.close
      expect(client.registered?("UI", "Brand new")).to be(true)
      expect(client.has_pending?).to be(false)
    end

    it "on the rack.response_finished path, flushes from the callables and not from closing the body" do
      env, status, headers, body = call_app("/plan", "rack.response_finished" => [])
      read_body(body)
      body.close
      expect(client.registered?("UI", "Brand new")).to be(false)

      finish_response(env, status, headers)
      expect(client.registered?("UI", "Brand new")).to be(true)
    end

    it "on both paths, flushes only after Rails has completed the request" do
      seen = []
      allow(client).to receive(:flush_pending).and_wrap_original do |original, *args, **kwargs|
        seen << Langsys::Rails::CurrentLocale.locale
        original.call(*args, **kwargs)
      end

      _, _, _, body = call_app("/plan?locale=en-US")
      read_body(body)
      body.close

      RenderPlan.phrases = [["Brand new too", "UI"]]
      env, status, headers, body = call_app("/plan?locale=en-US", "rack.response_finished" => [])
      read_body(body)
      body.close
      finish_response(env, status, headers)

      expect(seen).to eq([nil, nil]) # CurrentAttributes were already cleared by the executor
    end
  end

  describe "SRV-3 — order of events" do
    before do
      stub_authorize(key_type: "write", write_enabled: true)
      stub_translations("en-us", { "UI" => { "Save" => "Save" } })
      stub_request(:post, REGISTRATION_URL).to_return do |request|
        tags = %w[A B].select { |tag| request.body.include?("Miss #{tag}") }
        EventLog.record("posted:#{tags.join(',')}")
        json_response({ "status" => true, "data" => [] })
      end
      client # built once, before any thread races to build it
    end

    def serve(tag)
      _, _, _, body = call_app("/events?tag=#{tag}")
      EventLog.record("#{tag}:response-returned")
      read_body(body)
      EventLog.record("#{tag}:body-sent")
      body.close
    end

    it "posts nothing before the response is sent, even when the render outlasts the core's debounce window" do
      EventsController.hold = ->(_tag) { sleep(Langsys::Discovery::DEBOUNCE_SECONDS + 0.2) }
      serve("A")
      expect(EventLog.events)
        .to eq(["A:miss-recorded", "A:rendered", "A:response-returned", "A:body-sent", "posted:A"])
    end

    it "does not let another request's flush collect a miss while its own render is still running" do
      holding = Queue.new
      release = Queue.new
      EventsController.hold = lambda do |tag|
        next unless tag == "A"

        holding << true
        release.pop
      end

      a = Thread.new { serve("A") }
      holding.pop
      serve("B")
      release << true
      a.join(10)

      events = EventLog.events
      posted_a = events.index { |event| event.start_with?("posted:") && event.include?("A") }
      expect(posted_a).not_to be_nil
      expect(posted_a).to be > events.index("A:response-returned")
    end
  end

  describe "SRV-3 — the request scope" do
    it "is open for the request that builds the client" do
      Langsys::Rails.reset_client!
      stub_authorize(key_type: "write", write_enabled: true)
      stub_translations("en-us", { "UI" => {} })
      stub_registration
      RenderPlan.phrases = [["Built mid-request", "UI"]]
      _, _, _, body = call_app("/plan")
      built = Langsys::Rails.client
      expect(built.flush_pending["reason"]).to eq("held_by_request")
      read_body(body)
      body.close
      expect(built.registered?("UI", "Built mid-request")).to be(true)
    end

    it "is released when the application raises, so its misses are not held until shutdown" do
      stub_authorize(key_type: "write", write_enabled: true)
      stub_translations("en-us", { "UI" => {} })
      stub_registration
      failing = described_class.new(lambda do |_env|
        Langsys::Rails.t("Seen before the error", "UI")
        raise "boom"
      end)
      expect { failing.call(Rack::MockRequest.env_for("/")) }.to raise_error("boom")
      expect(client.flush_pending["success"]).to be(true)
      expect(client.registered?("UI", "Seen before the error")).to be(true)
    end
  end

  describe "GATE-3 — the write decision does not outlive the request" do
    before { stub_translations("en-us", { "UI" => { "Save" => "Save" } }, write_enabled: true) }

    it "is dropped once the request is done, though the render recorded one" do
      RenderPlan.phrases = [%w[Save UI]]
      get "/plan"
      expect(RenderPlan.signal_after_render).to be(true) # positive control: there was a decision to drop
      expect(client.write_signal).to be_nil
    end

    it "drops a decision recorded outside any request before the request can read it" do
      client.t("Save", category: "UI")
      expect(client.write_signal).to be(true) # positive control
      seen = :unset
      boundary = described_class.new(lambda do |_env|
        seen = client.write_signal
        [200, {}, ["ok"]]
      end)
      _, _, body = boundary.call(Rack::MockRequest.env_for("/"))
      body.close
      expect(seen).to be_nil
    end
  end

  describe "BIND-2 — the boundary leaves the capability decision to the core" do
    it "does not discard a read-only session's queue; the core decides what happens to it" do
      stub_authorize(key_type: "read", write_enabled: false)
      stub_translations("en-us", { "UI" => {} })
      RenderPlan.phrases = [["Only discovered", "UI"]]
      get "/plan"
      expect(client.registered?("UI", "Only discovered")).to be(false)
      expect(client.has_pending?).to be(true)
    end
  end
end
