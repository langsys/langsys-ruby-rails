# frozen_string_literal: true

require "spec_helper"
require "support/test_app"

# Legacy-key migration through I18n.t (MIG-1, MIG-2, MIG-8).
RSpec.describe Langsys::Rails::I18nBridge do
  let(:source_file) { File.expand_path("fixtures/en.yml", __dir__) }
  let(:client) { Langsys::Rails.client }

  around do |example|
    original = I18n.backend
    example.run
  ensure
    I18n.backend = original
  end

  before do
    stub_translations("en-us", { "checkout" => {}, "cart" => {} })
    I18n.backend.store_translations(:en, errors: { messages: { blank: "can't be blank" } })
  end

  def migrate!
    configure_langsys(**APP_SETTINGS, migration: [source_file], migration_locale: "en")
    described_class.install!
  end

  def queued = client.pending_phrases

  describe "MIG-1 — off unless configured" do
    it "leaves I18n alone, and consults no migration file, when the mode is unset" do
      configure_langsys(**APP_SETTINGS)
      expect(I18n.backend).not_to be_a(described_class)
      expect(client.migration).to be_nil
      expect(I18n.t("checkout.submit")).to eq("Translation missing: en.checkout.submit")
      expect(queued).to be_empty
    end
  end

  describe "MIG-2 — a key first, then literal text" do
    before { migrate! }

    it "answers a key in the source file with its value's phrase, under the key's namespace, never the key" do
      expect(I18n.t("checkout.submit")).to eq("Place order")
      expect(queued).to eq([{ "phrase" => "Place order", "category" => "checkout" }])
    end

    it "converts a key's Rails plural to one ICU phrase" do
      expect(I18n.t("cart.items", count: 3)).to eq("3 items")
      expect(queued.first["phrase"]).to eq("{count, plural, =0 {Your cart is empty} one {# item} other {# items}}")
    end

    it "treats a literal string as source text, converting the %{name} placeholders it passes" do
      expect(I18n.t("Welcome back, %{name}", name: "Ada")).to eq("Welcome back, Ada")
      I18n.t("Welcome back, %{name}", name: "Ada")
      Langsys::Rails.t("Welcome back, {name}", name: "Ada")
      expect(queued.map { |p| p["phrase"] }.uniq).to eq(["Welcome back, {name}"])
    end

    it "leaves Rails' own keys, and scoped or defaulted lookups, to the I18n backend" do
      expect(I18n.t("errors.messages.blank")).to eq("can't be blank")
      expect(I18n.t(:blank, scope: "errors.messages")).to eq("can't be blank")
      expect(I18n.t("no.such.key", default: "fallback")).to eq("fallback")
      expect(queued).to be_empty
    end
  end

  describe "MIG-8 — one contract behind every entry point" do
    before { migrate! }

    it "gives a key through I18n.t the same phrase and category as the base SDK's translate_legacy" do
      I18n.t("checkout.greeting", name: "Ada")
      through_i18n = queued
      client.clear_pending
      client.translate_legacy("checkout.greeting", entry_point: :rails, params: { name: "Ada" })
      expect(queued).to eq(through_i18n)
      expect(through_i18n).to eq([{ "phrase" => "Hello {name}, your order is ready", "category" => "checkout" }])
    end
  end
end
