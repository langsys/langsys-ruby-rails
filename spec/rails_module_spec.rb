# frozen_string_literal: true

require "spec_helper"

RSpec.describe Langsys::Rails do
  describe ".t" do
    it "translates for the current request locale" do
      configure_langsys
      stub_translations("es-ES", { "UI" => { "Save" => "Guardar" } })
      Langsys::Rails::CurrentLocale.locale = "es-ES"
      expect(described_class.t("Save", "UI")).to eq("Guardar")
    end

    it "interpolates keyword params" do
      configure_langsys
      stub_translations("en-US", { "Greetings" => {} })
      expect(described_class.t("Hello, {name}!", "Greetings", name: "Sarah")).to eq("Hello, Sarah!")
    end
  end

  describe ".handle_pending" do
    it "drops the queue on a read key without writing" do
      configure_langsys
      stub_authorize(key_type: "read")
      stub_translations("en-US", { "UI" => {} })
      described_class.t("A new phrase", "UI") # queued
      expect(described_class.client.has_pending?).to be true
      described_class.handle_pending
      expect(described_class.client.has_pending?).to be false
      expect(a_request(:post, "https://api.test/api/translatable-items")).not_to have_been_made
    end

    it "registers the queue on a write key" do
      configure_langsys
      stub_authorize(key_type: "write")
      stub_translations("en-US", { "UI" => {} })
      post = stub_request(:post, "https://api.test/api/translatable-items")
             .to_return(status: 200, body: JSON.generate({ "status" => true, "data" => [] }))
      described_class.t("A new phrase", "UI")
      described_class.handle_pending
      expect(post).to have_been_made
    end
  end

  describe ".configure" do
    it "rebuilds the client with the new configuration" do
      configure_langsys(base_locale: "en-US")
      first = described_class.client
      configure_langsys(base_locale: "es-ES")
      expect(described_class.client).not_to equal(first)
    end
  end
end
