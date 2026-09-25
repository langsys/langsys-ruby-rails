# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "digest"

# The fleet's API contract double (spec CONF-2), vendored byte-exact under spec/contract-fixture
# from langsys-js-typescript, git tree TREE. One Node process per spec group. The SDK points its
# API base at +base_url+ (WIRE-5); a test asserts on status and on accepted state read back,
# never on error text.
class ContractFixture
  TREE = "542f57f5ffcb9038db1b7411152b7e31b96cb269"
  DIR = File.expand_path("../contract-fixture", __dir__)
  FILES = %w[README.md seed.schema.json server.mjs].freeze

  attr_reader :base_url

  # The git tree id of the vendored directory, computed from the files on disk the way git
  # hashes blobs and trees, so the check needs no repository.
  def self.vendored_tree
    entries = FILES.sort.map do |name|
      content = File.binread(File.join(DIR, name))
      blob = Digest::SHA1.digest("blob #{content.bytesize}\0#{content}")
      "100644 #{name}\0".b + blob
    end.join
    Digest::SHA1.hexdigest("tree #{entries.bytesize}\0".b + entries)
  end

  def self.start = new.tap(&:boot)

  def boot
    @stdin, @stdout, @thread = Open3.popen2("node", File.join(DIR, "server.mjs"))
    line = @stdout.gets or raise "contract fixture exited before it was ready"
    ready = JSON.parse(line)
    raise "contract fixture not ready: #{line}" unless ready["ready"]

    @base_url = ready["base_url"]
    @fixture_url = ready["fixture_url"]
    Thread.new { @stdout.each_line { nil } } # a full pipe must never block the double
    self
  end

  def stop
    Process.kill("TERM", @thread.pid)
    @thread.join(5)
  rescue Errno::ESRCH
    nil
  end

  def seed(document) = fixture(:post, "seed", document)
  def reset = fixture(:post, "reset", {})
  def state = fixture(:get, "state")

  private

  def fixture(verb, path, body = nil)
    uri = URI("#{@fixture_url}/#{path}")
    response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(build(verb, uri, body)) }
    raise "fixture #{path} answered #{response.code}: #{response.body}" unless response.code.to_i < 300

    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  end

  def build(verb, uri, body)
    return Net::HTTP::Get.new(uri) if verb == :get

    Net::HTTP::Post.new(uri, "Content-Type" => "application/json").tap { |req| req.body = JSON.generate(body) if body }
  end
end

# `contract: true` on a describe block starts one double for the group.
RSpec.shared_context "contract fixture" do
  before(:context) { @contract = ContractFixture.start }
  after(:context) { @contract&.stop }
  before { @contract.reset }

  let(:contract) { @contract }
end
RSpec.configure { |c| c.include_context "contract fixture", contract: true }
