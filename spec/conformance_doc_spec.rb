# frozen_string_literal: true

require "spec_helper"

# CONFORMANCE.md is a claim about this binding. This file keeps the claim's FORM honest, so a
# malformed or self-contradicting document fails the build rather than the reader: the
# canonical header rows, one status table grading each of the spec's 79 rule ids exactly once,
# the status and tier vocabulary and which tiers each status may carry, and a summary computed
# from the table instead of typed beside it.
module ConformanceDoc
  PATH = File.expand_path("../CONFORMANCE.md", __dir__)

  SPEC_BLOB = "5c5c0723f88fb8e6b13f58876c7adca8b6b35691"

  # The rule ids of docs/sdk-spec.mdx at SPEC_BLOB, in document order. Derived, not recalled:
  #   git -C ../langsys2 cat-file blob 5c5c0723 | grep -oE '^### [A-Z]+-[0-9]+ ' | cut -c5- | tr -d ' '
  # Hard-coded because the spec lives in a sibling repo that need not be present at test time.
  RULE_IDS = %w[
    GATE-1 GATE-2 GATE-3 GATE-4 GATE-5 GATE-6 GATE-7 GATE-8 CAT-1 CAT-2
    CAT-3 REG-1 REG-2 REG-3 REG-4 REG-5 REG-6 REG-7 REG-8 REG-9
    REG-10 REG-11 REG-12 HINT-1 HINT-2 HINT-3 HINT-4 HINT-5 HINT-6 HINT-7
    HINT-8 HINT-9 HINT-10 HINT-11 HINT-12 ICU-1 ICU-2 ICU-3 ICU-4 ICU-5
    CID-1 CID-2 CID-3 CID-4 TOK-1 TOK-2 TOK-3 TOK-4 TOK-5 MARK-1
    MARK-2 SSR-1 SSR-2 SSR-3 SRV-1 SRV-2 SRV-3 SRV-4 SRV-5 BIND-1
    BIND-2 BIND-3 BIND-4 BIND-5 BIND-6 GRANT-1 GRANT-2 GRANT-3 GRANT-4 CACHE-1
    OBS-1 WIRE-1 WIRE-2 WIRE-3 WIRE-4 WIRE-5 CONF-1 CONF-2 CONF-3
  ].freeze

  HEADER_ROWS = [
    "| **Spec revision read** | langsys2 5cff03a1…, docs/sdk-spec.mdx blob #{SPEC_BLOB} |",
    "| **Profiles** | server, binding, all — derived: binding over langsys-ruby |"
  ].freeze

  STATUSES = ["implemented", "provisional", "delegated", "partial", "not implemented",
              "held (strip ruling)", "waived"].freeze
  TIERS = ["live", "contract", "mock", "n/a (pure)", "-"].freeze

  # A binding over a server core is every profile but `browser`, so that is the only profile
  # this file may skip a rule on.
  PROFILE_NA = "n/a (profile: browser)"
  ARCHITECTURE_NA = %r{\An/a \(architecture: .+live if .+\)\z}

  TIERS_FOR = {
    "implemented" => ["live", "contract", "n/a (pure)"],
    "provisional" => ["mock"],
    "delegated" => ["-"],
    "not implemented" => ["-"],
    "waived" => ["-"],
    PROFILE_NA => ["-"]
  }.freeze

  Row = Struct.new(:rule, :status, :tier, :evidence)

  module_function

  def text = File.read(PATH)

  def table_headers = text.lines.grep(/\A\| Rule \| Status \| Tier \| Evidence \|/)

  def rows
    body = text[/^\| Rule \| Status \| Tier \| Evidence \|\n\|[-| ]+\|\n((?:\|.*\n)+)/, 1].to_s
    body.each_line.map do |line|
      Row.new(*line.strip.delete_prefix("| ").delete_suffix(" |").split(" | ", 4).map(&:strip))
    end
  end

  def bucket(status)
    status.match?(ARCHITECTURE_NA) ? "n/a (architecture)" : status
  end

  def tally
    rows.each_with_object(Hash.new(0)) { |row, counts| counts[bucket(row.status)] += 1 }
  end

  def summary
    section = text[/^## Summary\n(.*?)(?=^## |\z)/m, 1].to_s
    section.each_line.filter_map do |line|
      next unless line =~ /\A\| ([^|*]+?) \| (\d+) \|/

      [Regexp.last_match(1).strip, Regexp.last_match(2).to_i]
    end.to_h
  end
end

RSpec.describe "CONFORMANCE.md" do
  let(:rows) { ConformanceDoc.rows }

  it "derives from a spec blob whose rule list is intact" do
    expect(ConformanceDoc::RULE_IDS.size).to eq(79)
    expect(ConformanceDoc::RULE_IDS.uniq.size).to eq(79)
  end

  it "carries the canonical header rows" do
    ConformanceDoc::HEADER_ROWS.each { |row| expect(ConformanceDoc.text.lines.map(&:chomp)).to include(row) }
  end

  it "has exactly one status table" do
    expect(ConformanceDoc.table_headers.size).to eq(1)
  end

  it "grades every rule in the spec exactly once, one id per row, in spec order" do
    expect(rows.map(&:rule)).to eq(ConformanceDoc::RULE_IDS)
  end

  it "uses only the canonical statuses" do
    unknown = rows.reject do |row|
      ConformanceDoc::STATUSES.include?(row.status) || row.status == ConformanceDoc::PROFILE_NA ||
        row.status.match?(ConformanceDoc::ARCHITECTURE_NA)
    end
    expect(unknown.map { |row| [row.rule, row.status] }).to be_empty
  end

  it "uses only the canonical tiers, and only those each status permits" do
    wrong = rows.reject do |row|
      permitted = ConformanceDoc::TIERS_FOR.fetch(row.status) do
        row.status.match?(ConformanceDoc::ARCHITECTURE_NA) ? ["-"] : ConformanceDoc::TIERS
      end
      ConformanceDoc::TIERS.include?(row.tier) && permitted.include?(row.tier)
    end
    expect(wrong.map { |row| [row.rule, row.status, row.tier] }).to be_empty
  end

  it "gives every row evidence" do
    expect(rows.select { |row| row.evidence.to_s.empty? }.map(&:rule)).to be_empty
  end

  it "has a summary computed from the table" do
    claimed = ConformanceDoc.summary
    expect(claimed.delete("total")).to eq(rows.size)
    expect(claimed).to eq(ConformanceDoc.tally)
  end
end
