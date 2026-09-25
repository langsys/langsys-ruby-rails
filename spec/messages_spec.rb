# frozen_string_literal: true

require "spec_helper"
require "support/test_app"
require "support/models"

# Server messages from ActiveModel validation (MSG-1..11): entries built from the failed rules,
# the reference wording with labels written in, and the build-time listing.
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

  describe "MSG-9 — entries are built from the rules that failed, not from Rails' text" do
    it "yields one entry per failed rule on a field, with the codes and params of those rules" do
      entries = entries_for(signup(email: "abc"))
      expect(entries).to eq([
                              { "field" => "email", "code" => "too_short",
                                "message" => "The email address must be at least 5 characters.",
                                "template" => "The email address must be at least {min} characters.",
                                "params" => { "min" => 5 } },
                              { "field" => "email", "code" => "invalid_format",
                                "message" => "The email address format is invalid.",
                                "template" => "The email address format is invalid." }
                            ])
    end

    it "never takes a template from the message Rails rendered" do
      record = signup(email: "abc")
      record.valid?
      rendered = record.errors.full_messages
      expect(described_class.entries(record).map { |e| e["template"] } & rendered).to be_empty
    end

    it "turns a failure that arrives with text only into code invalid, its sentence the template" do
      record = signup
      record.errors.add(:base, "Something upstream broke.")
      expect(described_class.entries(record)).to eq([{ "code" => "invalid", "message" => "Something upstream broke.",
                                                       "template" => "Something upstream broke." }])
    end
  end

  describe "MSG-2 — codes from the shared vocabulary, size codes by the field's type" do
    it "uses MSG-2's wording for an exclusive upper bound, and min for an inclusive lower one" do
      expect(entries_for(signup(age: 200)).first).to include("code" => "too_large",
                                                             "template" => "The age must be less than {value}.",
                                                             "params" => { "value" => 130 })
      expect(entries_for(signup(age: 10)).first).to include("code" => "too_small",
                                                            "template" => "The age must be at least {min}.",
                                                            "params" => { "min" => 18 })
    end

    it "picks the size code by type: text too_short, numbers too_small, lists too_many" do
      expect(entries_for(signup(email: "a@b")).first["code"]).to eq("too_short")
      expect(entries_for(signup(age: 10)).first["code"]).to eq("too_small")
      expect(entries_for(signup(tags: %w[a b c])).first)
        .to include("code" => "too_many", "template" => "The tags must not have more than {max} items.")
    end

    it "gives a date bound the date wording, with the date as a non-translatable param" do
      expect(entries_for(signup(starts_on: Date.new(2025, 1, 1))).first)
        .to include("code" => "invalid_date", "template" => "The start date must be after {date}.",
                    "params" => { "date" => "2026-01-01" })
    end

    it "draws every code from the vocabulary" do
      record = signup(email: "", age: 200, tags: %w[a b c], starts_on: Date.new(2025, 1, 1),
                      password: "x", password_confirmation: "y")
      codes = entries_for(record).map { |e| e["code"] }
      expect(codes - Langsys::Messages::CODES).to be_empty
    end
  end

  describe "MSG-3 / MSG-10 — whole sentences, the framework's label written in" do
    it "writes human_attribute_name into the sentence, so each label is its own phrase" do
      email = entries_for(signup(email: nil)).first
      expect(email["template"]).to eq("The email address is required.")
      I18n.backend.store_translations(:en, activemodel: { attributes: { signup: { email: "e-mail" } } })
      expect(entries_for(signup(email: nil)).first["template"]).to eq("The e-mail is required.")
    end

    it "names the confirmed field, not the confirmation field, in a mismatch" do
      entry = entries_for(signup(password: "x", password_confirmation: "y")).first
      expect(entry).to include("field" => "password_confirmation", "code" => "mismatch",
                               "template" => "The password confirmation does not match.")
    end
  end

  describe "MSG-1 / MSG-4 — four fixed pieces; params fill markers; message is the filled template" do
    it "carries only the fixed keys, numbers as numbers, and params only when there are markers" do
      entries = entries_for(signup(email: nil, age: 200))
      entries.each { |e| expect(e.keys - %w[field code message template params]).to be_empty }
      required = entries.find { |e| e["code"] == "required" }
      expect(required).not_to have_key("params")
      expect(required["message"]).to eq(required["template"])
      bound = entries.find { |e| e["code"] == "too_large" }
      expect(bound["params"]["value"]).to be_a(Integer)
      expect(bound["message"]).to eq(Langsys::Messages.fill(bound["template"], bound["params"]))
    end

    it "writes a nested attribute as a dotted path, and a whole-record failure with no field" do
      record = signup
      record.errors.add(:"items[3].label", :blank)
      record.errors.add(:base, :invalid)
      fields = described_class.entries(record).map { |e| e["field"] }
      expect(fields).to eq(["items.3.label", nil])
    end
  end

  describe "MSG-7 / MSG-10 / MSG-11 — the build-time listing" do
    def listing(*classes)
      out = StringIO.new
      status = Langsys::Messages::Command.run(sources: [Langsys::Rails::ValidatorSource.new(classes)], out: out)
      [status, out.string]
    end

    it "lists every template a model's validators can emit, with zero problems" do
      status, out = listing(Signup)
      expect(status).to eq(0)
      expect(out).to include("✓ The email address is required.",
                             "✓ The email address must be at least {min} characters.",
                             "✓ The age must be less than {value}.", "✓ The age must be at least {min}.",
                             "✓ The tags must not have more than {max} items.",
                             "✓ The start date must be after {date}.", "✓ The password confirmation does not match.")
      expect(out).not_to include("✗")
    end

    it "exits non-zero naming a custom rule whose templates are not declared, with the fix" do
      status, out = listing(SignupWithCustomRule)
      expect(status).to eq(1)
      expect(out).to match(/✗ SignupWithCustomRule: custom rule validate :not_on_a_holiday .*langsys_message_templates/)
    end

    it "lists a custom rule's declared templates" do
      status, out = listing(SignupWithDeclaredRule)
      expect(status).to eq(0)
      expect(out).to include("✓ The start date cannot be a holiday.")
    end

    it "names a validated field with no declared label rather than guessing one from its key" do
      status, out = listing(Unlabelled)
      expect(status).to eq(1)
      expect(out).to include("✗ Unlabelled.cc_number: no label is declared")
      expect(out).not_to include("Cc number")
    end

    it "refuses a declared template carrying a label marker or a framework placeholder" do
      bad = Class.new(SignupWithCustomRule) do
        def self.name = "BadTemplates"

        def self.langsys_message_templates
          { starts_on: ["The {field} cannot be a holiday.", "The :attribute cannot be a holiday."] }
        end
      end
      I18n.backend.store_translations(:en, activemodel: { attributes: { bad_templates: labels } })
      status, out = listing(bad)
      expect(status).to eq(1)
      expect(out).to include("marker {field} carries a label", "framework placeholder :attribute")
    end
  end

  describe "MSG-5 — rendering an entry in a view" do
    let(:entry) { entries_for(signup(age: 200)).first }

    it "renders the catalog's translation of the template, filled from its params" do
      Langsys::Rails::CurrentLocale.locale = "es-ES"
      stub_translations("es-es",
                        { "Errors" => { "The age must be less than {value}." =>
                                          "La edad debe ser menor que {value}." } })
      helper = Object.new.extend(Langsys::Rails::Helper)
      expect(helper.ls_message(entry)).to eq("La edad debe ser menor que 130.")
    end

    it "falls back to message with no translation, and never looks message up" do
      Langsys::Rails::CurrentLocale.locale = "es-ES"
      stub_translations("es-es", { "Errors" => { "The age must be less than 130." => "trampa" } })
      helper = Object.new.extend(Langsys::Rails::Helper)
      expect(helper.ls_message(entry)).to eq("The age must be less than 130.")
    end
  end
end
