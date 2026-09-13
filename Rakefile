# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  # Hermetic by default; the live specs run with `rake integration`.
  t.rspec_opts = "--tag ~integration"
end

RSpec::Core::RakeTask.new(:integration) do |t|
  t.rspec_opts = "--tag integration"
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
  # rubocop not installed — skip the lint task
end

desc "Validate the RBS type signatures in sig/"
task :rbs do
  sh "rbs -I sig validate"
end

task default: %i[spec]

namespace :mutation do
  def run_mutations(live:)
    require_relative "spec/mutation/harness"
    require_relative "spec/mutation/manifest"
    entries = Mutation::MANIFEST.select { |entry| entry.fetch(:live, false) == live }
    killed = Mutation.run(entries)
    abort "mutation: #{entries.size - killed} mutant(s) survived" unless killed == entries.size
  end

  desc "CONF-3: apply each hermetic mutation and require its examples to go red"
  task(:hermetic) { run_mutations(live: false) }

  desc "CONF-3: the live mutations — needs the LANGSYS_* credentials of spec/integration/live_spec.rb"
  task(:live) { run_mutations(live: true) }
end

desc "CONF-3: the hermetic mutation run"
task mutation: "mutation:hermetic"
