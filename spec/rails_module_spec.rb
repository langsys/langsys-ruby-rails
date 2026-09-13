# frozen_string_literal: true

require "spec_helper"

RSpec.describe Langsys::Rails do
  describe ".t" do
    it "translates for the current request locale" do
      configure_langsys
      stub_translations("es-es", { "UI" => { "Save" => "Guardar" } })
      Langsys::Rails::CurrentLocale.locale = "es-ES"
      expect(described_class.t("Save", "UI")).to eq("Guardar")
    end

    it "interpolates keyword params" do
      configure_langsys
      stub_translations("en-us", { "Greetings" => {} })
      expect(described_class.t("Hello, {name}!", "Greetings", name: "Sarah")).to eq("Hello, Sarah!")
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
