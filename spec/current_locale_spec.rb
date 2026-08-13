# frozen_string_literal: true

require "spec_helper"

RSpec.describe Langsys::Rails::CurrentAttributesLocaleSource do
  subject(:source) { described_class.new }

  it "returns an empty string when the request locale is unset" do
    expect(source.get).to eq("")
  end

  it "reflects the request-scoped CurrentLocale" do
    Langsys::Rails::CurrentLocale.locale = "es-ES"
    expect(source.get).to eq("es-ES")
  end

  it "fires a subscriber immediately with the current value" do
    Langsys::Rails::CurrentLocale.locale = "fr-FR"
    seen = []
    source.subscribe(->(v) { seen << v })
    expect(seen).to eq(["fr-FR"])
  end
end
