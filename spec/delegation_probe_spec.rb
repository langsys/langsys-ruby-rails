# frozen_string_literal: true

require "spec_helper"

# Absence probes behind the `delegated` rows in CONFORMANCE.md, and behind the probe half of
# BIND-2 and BIND-3.
#
# A delegated rule is the core's to satisfy; this binding's obligation is not to take part.
# Each probe searches the binding's code for the mechanism the rule governs and must find
# nothing. Each also carries a FIRING CONTROL: the same pattern over the core's code, which
# implements that mechanism, must find it. A probe whose control finds nothing is reading
# nothing, and its absences mean nothing.
#
# Full-line comments are dropped on both sides, so prose that names a rule is not counted
# as taking part in it; code is.
module DelegationProbe
  BINDING_LIB = File.expand_path("../lib", __dir__)
  CORE_LIB = File.join(Gem.loaded_specs.fetch("langsys").full_gem_path, "lib")

  PROBES = [
    { rules: %w[GATE-1 GATE-8 REG-1 BIND-2], name: "capability decision",
      pattern: /can_write\?|write_enabled|write_signal|key_type/ },
    { rules: %w[GATE-2 GATE-5 REG-6 REG-7 REG-8], name: "queue bookkeeping",
      pattern: /clear_pending|registered\?|begin_send|end_send|penalise|snapshot|backing_off\?|reset_backoff!/ },
    { rules: %w[GATE-4 CACHE-1], name: "cache writes and keys",
      pattern: /@cache\.(?:set|write|delete|clear)|\bcache_key\b/ },
    { rules: %w[CAT-1 CAT-2 CAT-3 REG-12], name: "catalog inspection",
      pattern: /Catalog\.resolve|existing_keys|\.key\?\(|is_a\?\(Hash\)/ },
    { rules: %w[REG-2 BIND-3], name: "send scheduling",
      pattern: /flush_if_due|flush_due\?|\bdebounce\b|\bsleep\b|Thread\.new|\bTimer\b/ },
    { rules: %w[REG-9 BIND-3], name: "batching", pattern: /batch_limit|each_slice/ },
    { rules: %w[REG-10], name: "failure handling", pattern: /\brescue\b|\.warn\(|\.error\(/ },
    { rules: %w[REG-11], name: "ellipsis handling", pattern: /Ellipsis|ellipsis_stem|truncated_twin\?/ },
    { rules: %w[HINT-2 WIRE-1 WIRE-2 WIRE-3 BIND-3], name: "request construction",
      pattern: %r{Net::HTTP|Http\.new|X-Authorization|normalize_locale|Content-Type|discovery/hint} },
    { rules: %w[ICU-1 ICU-2 ICU-3 ICU-4 ICU-5], name: "interpolation",
      pattern: /\bInterpolate\b|TwitterCldr|\bCldr\b/ },
    { rules: %w[CID-1 CID-2 CID-3 CID-4], name: "content-block identity", pattern: /Digest::MD5|custom_id|\bmd5\b/ },
    { rules: %w[TOK-1 TOK-2 TOK-3 TOK-4 TOK-5 MARK-1 MARK-2 SRV-5], name: "tokenizer and host identity",
      pattern: /Nokogiri|data-ls-|data-langsys-|TRANSLATABLE_ATTRIBUTES|tokeni[sz]e/ }
  ].freeze

  module_function

  def sources(root)
    Dir.glob(File.join(root, "**", "*.rb")).to_h do |path|
      [path.delete_prefix("#{root}/"), File.readlines(path).grep_v(/\A\s*#/).join]
    end
  end

  def hits(root, pattern)
    sources(root).flat_map { |path, code| code.scan(pattern).map { |match| "#{path}: #{match}" } }
  end
end

RSpec.describe "Delegated rules: absence probes with firing controls" do
  it "reads both the binding's code and the core's code" do
    expect(DelegationProbe.sources(DelegationProbe::BINDING_LIB).size).to be >= 9
    expect(DelegationProbe.sources(DelegationProbe::CORE_LIB).size).to be >= 20
  end

  DelegationProbe::PROBES.each do |probe|
    describe "#{probe[:name]} (#{probe[:rules].join(', ')})" do
      it "finds the mechanism in the core (firing control)" do
        expect(DelegationProbe.hits(DelegationProbe::CORE_LIB, probe[:pattern])).not_to be_empty
      end

      it "finds no participation in the binding" do
        expect(DelegationProbe.hits(DelegationProbe::BINDING_LIB, probe[:pattern])).to be_empty
      end
    end
  end
end
