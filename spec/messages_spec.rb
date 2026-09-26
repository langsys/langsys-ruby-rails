# frozen_string_literal: true

require "spec_helper"
require "support/test_app"
require "support/models"

# Server messages from ActiveModel validation (MSG-1..11): Rails' own sentences, unfilled, with
# the label written in where Rails writes it, and the build-time listing.
RSpec.describe Langsys::Rails::Messages do
  include Rack::Test::Methods

  def app = LangsysTestApp

  let(:client) { Langsys::Rails.client }
  let(:labels) do
    { email: "email address", age: "age", tags: "tags", starts_on: "start date", password: "password",
      password_confirmation: "password confirmation" }
  end

  before do
    I18n.backend.store_translations(:en, activemodel: { attributes: {
                                      signup: labels, signup_with_custom_rule: labels, signup_with_declared_rule: labels
                                    } })
    configure_langsys(**APP_SETTINGS)
    stub_translations("en-us", { "Errors" => {} })
  end

  after { I18n.reload! }

  def signup(**attributes)
    Signup.new({ email: "someone@example.test", age: 30, tags: [], starts_on: Date.new(2026, 6, 1) }.merge(attributes))
  end

  def entries_for(record)
    record.valid?
    described_class.entries(record)
  end

  describe "MSG-9 / MSG-3 — Rails' own unfilled sentence, the label written in" do
    it "yields one entry per failure, each Rails' sentence with {count} as a marker and the count as a param" do
      expect(entries_for(signup(email: "abc"))).to eq(
        [{ "field" => "email", "code" => "too_short",
           "message" => "email address is too short (minimum is 5 characters)",
           "template" => "email address is too short (minimum is {count} characters)", "params" => { "count" => 5 } },
         { "field" => "email", "code" => "invalid", "message" => "email address is invalid",
           "template" => "email address is invalid" }]
      )
    end

    it "is Rails' rendered message exactly, once filled" do
      record = signup(email: "abc", age: 200)
      record.valid?
      expect(described_class.entries(record).map { |e| e["message"] }).to eq(record.errors.full_messages)
    end

    it "keeps the plural form Rails chose for the count" do
      record = signup
      record.errors.add(:email, :too_short, count: 1)
      expect(described_class.entries(record).first)
        .to include("template" => "email address is too short (minimum is 1 character)",
                    "message" => "email address is too short (minimum is 1 character)")
    end

    it "registers a failure that arrives as text only as that text, with no code and no params" do
      record = signup
      record.errors.add(:base, "Something upstream broke.")
      expect(described_class.entries(record)).to eq([{ "field" => "base", "message" => "Something upstream broke.",
                                                       "template" => "Something upstream broke." }])
    end

    it "turns an app's own interpolation value into a marker" do
      record = signup
      record.errors.add(:email, :too_many_tries, limit: 5, message: "must stay under %{limit} tries")
      expect(described_class.entries(record).first)
        .to include("code" => "too_many_tries", "template" => "email address must stay under {limit} tries",
                    "params" => { "limit" => 5 })
    end

    it "gives a date bound as an ISO date param" do
      expect(entries_for(signup(starts_on: Date.new(2025, 1, 1))).first)
        .to include("code" => "greater_than", "template" => "start date must be greater than {count}",
                    "params" => { "count" => "2026-01-01" })
    end
  end

  describe "MSG-2 — the code is Rails' own error key" do
    it "passes the error key through unchanged" do
      codes = entries_for(signup(email: "", age: 200, password: "x", password_confirmation: "y")).map { |e| e["code"] }
      expect(codes).to eq(%w[blank too_short invalid less_than confirmation])
    end
  end

  describe "MSG-10 — the label Rails itself prints" do
    it "writes the declared label in, one template per label" do
      expect(entries_for(signup(email: nil)).first["template"]).to eq("email address can't be blank")
      I18n.backend.store_translations(:en, activemodel: { attributes: { signup: { email: "e-mail" } } })
      expect(entries_for(signup(email: nil)).first["template"]).to eq("e-mail can't be blank")
    end

    it "uses the name Rails derives where no label is declared" do
      record = Unlabelled.new
      record.valid?
      expect(described_class.entries(record).first["template"]).to eq(record.errors.full_messages.first)
    end

    it "writes the confirmed field's label into a mismatch, as Rails does" do
      entry = entries_for(signup(password: "x", password_confirmation: "y")).first
      expect(entry).to include("field" => "password_confirmation", "code" => "confirmation",
                               "template" => "password confirmation doesn't match password")
    end
  end

  describe "MSG-1 / MSG-4 — template and params; the rest is Rails'" do
    it "carries numbers as numbers, params only with markers, and message the filled template" do
      entries = entries_for(signup(email: nil, age: 200))
      blank = entries.find { |e| e["code"] == "blank" }
      expect(blank).not_to have_key("params")
      expect(blank["message"]).to eq(blank["template"])
      bound = entries.find { |e| e["code"] == "less_than" }
      expect(bound["params"]["count"]).to be_a(Integer)
      expect(bound["message"]).to eq(Langsys::Messages.fill(bound["template"], bound["params"]))
    end

    it "keeps Rails' own field path, and words a nested failure as Rails renders it" do
      record = signup
      inner = signup(email: nil)
      inner.valid?
      record.errors.import(inner.errors.objects.first, attribute: "items[3].email")
      entry = described_class.entries(record).first
      expect(entry["field"]).to eq("items[3].email")
      expect(entry["template"]).to eq(record.errors.full_messages.first)
    end
  end

  describe "MSG-7 / MSG-10 / MSG-11 — the build-time listing" do
    def listing(*classes, strict: false)
      out = StringIO.new
      status = Langsys::Messages::Command.run(sources: [Langsys::Rails::ValidatorSource.new(classes)],
                                              out: out, strict: strict)
      [status, out.string]
    end

    it "lists, for each validator, exactly the template a failure at runtime produces" do
      status, out = listing(Signup)
      expect(status).to eq(0)
      runtime = entries_for(signup(email: "", age: 200, tags: %w[a b c], starts_on: Date.new(2025, 1, 1),
                                   password: "x", password_confirmation: "y")).map { |e| e["template"] }
      runtime.each { |template| expect(out).to include("✓ #{template}") }
    end

    it "reports a custom rule it cannot list, exiting zero, and non-zero under strict" do
      status, out = listing(SignupWithCustomRule)
      expect(status).to eq(0)
      expect(out).to match(/✗ SignupWithCustomRule: custom rule validate :not_on_a_holiday .*langsys_message_templates/)
      expect(listing(SignupWithCustomRule, strict: true).first).to eq(1)
    end

    it "lists a custom rule's declared templates" do
      status, out = listing(SignupWithDeclaredRule)
      expect(status).to eq(0)
      expect(out).to include("✓ The start date cannot be a holiday.")
    end

    it "names a validated field with no declared label as advice, never failing, even under strict" do
      status, out = listing(Unlabelled, strict: true)
      expect(status).to eq(0)
      expect(out).to include("Unlabelled.cc_number", "no label is declared")
    end

    it "refuses a declared template still holding Rails' label placeholder" do
      bad = Class.new(SignupWithCustomRule) do
        def self.name = "BadTemplates"

        def self.langsys_message_templates
          { starts_on: ["%{attribute} cannot be a holiday."] }
        end
      end
      I18n.backend.store_translations(:en, activemodel: { attributes: { bad_templates: labels } })
      _, out = listing(bad)
      expect(out).to include("✗ BadTemplates.starts_on")
      expect(out).not_to include("✓ %{attribute} cannot be a holiday.")
    end
  end

  describe "MSG-5 — rendering an entry in a view" do
    let(:entry) { entries_for(signup(age: 200)).first }

    it "renders the catalog's translation of the template, filled from its params" do
      Langsys::Rails::CurrentLocale.locale = "es-ES"
      stub_translations("es-es",
                        { "Errors" => { "age must be less than {count}" => "la edad debe ser menor que {count}" } })
      helper = Object.new.extend(Langsys::Rails::Helper)
      expect(helper.ls_message(entry)).to eq("la edad debe ser menor que 130")
    end

    it "falls back to message with no translation, and never looks message up" do
      Langsys::Rails::CurrentLocale.locale = "es-ES"
      stub_translations("es-es", { "Errors" => { "age must be less than 130" => "trampa" } })
      helper = Object.new.extend(Langsys::Rails::Helper)
      expect(helper.ls_message(entry)).to eq("age must be less than 130")
    end
  end
end
