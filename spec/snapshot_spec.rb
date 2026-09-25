# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "support/test_app"

# SNAP-2: a snapshot seeds the core's catalog when the app boots.
RSpec.describe "Catalog snapshot" do
  include Rack::Test::Methods

  def app = LangsysTestApp

  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  def write_snapshot(catalog, name: "snapshot.json")
    path = File.join(@dir, name)
    Langsys::Snapshot.new(project_id: "proj-1", generated_at: "2026-09-24T00:00:00Z", base_locale: "en-us",
                          locales: catalog.keys, categories: %w[UI], catalog: catalog).write(path)
    path
  end

  it "renders the first request from the snapshot, with no catalog fetch" do
    configure_langsys(**APP_SETTINGS, snapshot: write_snapshot({ "es-es" => { "UI" => { "Save" => "Guardar" } } }))
    Langsys::Rails::Railtie.seed_snapshot!
    get "/greet?locale=es-ES"
    expect(last_response.body).to eq("Guardar")
    expect(a_request(:get, TRANSLATIONS_URL).with(query: hash_including({}))).not_to have_been_made
  end

  it "builds the client at boot when a snapshot is configured, and not otherwise" do
    configure_langsys(**APP_SETTINGS)
    Langsys::Rails::Railtie.seed_snapshot!
    expect(Langsys::Rails.send(:built_client)).to be_nil

    configure_langsys(**APP_SETTINGS, snapshot: write_snapshot({ "es-es" => { "UI" => {} } }))
    Langsys::Rails::Railtie.seed_snapshot!
    expect(Langsys::Rails.send(:built_client)).to be_a(Langsys::Client)
  end

  it "fails the boot, naming the reason, when the snapshot was edited" do
    path = write_snapshot({ "es-es" => { "UI" => { "Save" => "Guardar" } } })
    File.write(path, File.read(path).sub("Guardar", "Salvar"))
    configure_langsys(**APP_SETTINGS, snapshot: path)
    expect { Langsys::Rails::Railtie.seed_snapshot! }.to raise_error(Langsys::ConfigurationError, /checksum/)
  end
end
