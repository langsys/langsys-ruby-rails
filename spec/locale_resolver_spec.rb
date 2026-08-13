# frozen_string_literal: true

require "spec_helper"

RSpec.describe Langsys::Rails::LocaleResolver do
  let(:config) do
    Langsys::Rails::Config.new.tap { |c| c.supported = %w[en-US es-ES] }
  end
  let(:resolver) { described_class.new(config) }
  let(:client) { instance_double(Langsys::Client) }

  it "prefers an explicit query param and marks it for persistence (canonicalized)" do
    locale, persist = resolver.resolve(query: "es-es", cookie: nil, accept_language: nil, client: client)
    expect(locale).to eq("es-ES")
    expect(persist).to be true
  end

  it "falls back to the cookie without persisting" do
    locale, persist = resolver.resolve(query: nil, cookie: "es-ES", accept_language: nil, client: client)
    expect(locale).to eq("es-ES")
    expect(persist).to be false
  end

  it "falls back to Accept-Language via the client" do
    allow(client).to receive(:detect_preferred_locale).with("es-ES,en;q=0.5", %w[en-US es-ES]).and_return("es-ES")
    locale, persist = resolver.resolve(query: nil, cookie: nil, accept_language: "es-ES,en;q=0.5", client: client)
    expect(locale).to eq("es-ES")
    expect(persist).to be false
  end

  it "returns a blank locale when nothing matches" do
    allow(client).to receive(:detect_preferred_locale).and_return(nil)
    locale, = resolver.resolve(query: nil, cookie: nil, accept_language: "de", client: client)
    expect(locale).to eq("")
  end
end
