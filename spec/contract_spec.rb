# frozen_string_literal: true

require "spec_helper"
require "support/test_app"
require "support/contract_fixture"

# Rows graded against the fleet's contract double, where the property depends on what the API
# answers: here, the catalog's translation of a server-message template.
RSpec.describe "Against the contract double", :contract do
  include Rack::Test::Methods

  def app = LangsysTestApp

  it "runs the fixture the fleet vendors, byte for byte" do
    expect(ContractFixture.vendored_tree).to eq(ContractFixture::TREE)
  end

  describe "MSG-5 — a failed form renders its entries in the request locale" do
    let(:plural) { "El correo debe tener al menos {count, plural, one {# carácter} other {# caracteres}}." }

    before do
      contract.seed(
        "projects" => [{ "id" => "proj-c", "base_locale" => "en-us", "target_locales" => ["es-es"],
                         "phrases" => [
                           { "category" => "Errors", "phrase" => "email address can't be blank",
                             "translations" => { "es-es" => "El correo electrónico es obligatorio." } },
                           { "category" => "Errors",
                             "phrase" => "email address is too short (minimum is {count} characters)",
                             "translations" => { "es-es" => plural } }
                         ] }],
        "keys" => [{ "key" => "w", "project" => "proj-c", "type" => "write" }]
      )
      configure_langsys(api_key: "w", project_id: "proj-c", api_url: contract.base_url, base_locale: "en-US")
      I18n.backend.store_translations(:en, activemodel: { attributes: { signup: { email: "email address" } } })
    end

    after { I18n.reload! }

    it "renders a translated template, filled through the catalog's ICU from a count param" do
      post "/signups?locale=es-ES", email: "a@b"
      expect(last_response.body).to eq("El correo debe tener al menos 5 caracteres.")
    end

    it "renders a translated template with no markers" do
      post "/signups?locale=es-ES", email: ""
      expect(last_response.body.lines.first.chomp).to eq("El correo electrónico es obligatorio.")
    end

    it "falls back to the entry's message where the catalog has no translation" do
      post "/signups?locale=es-ES", email: "abcde"
      expect(last_response.body).to eq("email address is invalid")
    end
  end
end
