# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

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
