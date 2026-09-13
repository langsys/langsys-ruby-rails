# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

# CONF-3: a runtime rule is proven by breaking it and watching its test go red.
#
# Each manifest entry is one source edit that breaks one behaviour, plus the examples that
# must go red under it. For every entry the harness:
#
# 1. requires `find` to occur EXACTLY ONCE in the file. A mutation that silently fails to
#    apply "survives" for the wrong reason;
# 2. runs the examples unmutated and requires them to pass, with more than zero run and
#    none pending. A red under mutation means nothing if they were red already, and a filter
#    matching nothing (or a live example skipped for want of credentials) reports no failure;
# 3. applies the edit and requires at least one failure with no load error. A mutant that
#    breaks loading proves nothing about any assertion;
# 4. restores the file byte for byte, in an `ensure`, and checks that it did.
module Mutation
  ROOT = File.expand_path("../..", __dir__)

  Result = Struct.new(:examples, :failures, :pending, :load_errors, :output, keyword_init: true) do
    def green? = examples.positive? && failures.zero? && pending.zero? && load_errors.zero?
    def killed? = failures.positive? && load_errors.zero?
  end

  module_function

  # Runs every entry; returns how many of its mutants were killed.
  def run(entries, out: $stdout)
    killed = entries.count { |entry| check(entry, out).killed? }
    out.puts "\n#{killed}/#{entries.size} mutants killed"
    killed
  end

  # Proves the entry applies once and its control is green, then returns the mutant's result.
  def check(entry, out)
    path = File.join(ROOT, entry.fetch(:file))
    original = File.binread(path)
    assert_applies_once(entry, original)
    control = green_control(entry)
    mutant = mutate(path, original, entry)
    report(out, entry, control, mutant)
    mutant
  end

  def green_control(entry)
    control = rspec(entry)
    return control if control.green?

    raise "#{entry[:id]}: control run is not green (#{describe(control)})\n#{control.output}"
  end

  def report(out, entry, control, mutant)
    out.puts format("%-8<verdict>s %-7<rule>s %-38<id>s control %<ce>d green, mutant %<mf>d/%<me>d red",
                    verdict: mutant.killed? ? "KILLED" : "SURVIVED", rule: entry[:rule], id: entry[:id],
                    ce: control.examples, mf: mutant.failures, me: mutant.examples)
  end

  def assert_applies_once(entry, source)
    count = source.scan(entry.fetch(:find)).size
    return if count == 1

    raise "#{entry[:id]}: `find` occurs #{count} times in #{entry[:file]}, expected exactly 1"
  end

  def mutate(path, original, entry)
    File.binwrite(path, original.sub(entry.fetch(:find)) { entry.fetch(:replace) })
    rspec(entry)
  ensure
    File.binwrite(path, original)
    raise "#{entry[:id]}: #{entry[:file]} was not restored" unless File.binread(path) == original
  end

  def rspec(entry)
    Dir.mktmpdir do |dir|
      report = File.join(dir, "report.json")
      output, = Open3.capture2e("bundle", "exec", "rspec", *entry.fetch(:examples),
                                "--format", "json", "--out", report, chdir: ROOT)
      summary = File.exist?(report) ? JSON.parse(File.read(report)).fetch("summary", {}) : {}
      Result.new(examples: summary.fetch("example_count", 0), failures: summary.fetch("failure_count", 0),
                 pending: summary.fetch("pending_count", 0),
                 load_errors: summary.fetch("errors_outside_of_examples_count", 1), output: output)
    end
  end

  def describe(result)
    "examples=#{result.examples} failures=#{result.failures} pending=#{result.pending} " \
      "load_errors=#{result.load_errors}"
  end
end
