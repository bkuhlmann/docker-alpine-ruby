# frozen_string_literal: true

require "git/lint/rake/register"
require "open3"
require "rubocop/rake_task"

Git::Lint::Rake::Register.call
RuboCop::RakeTask.new

desc "Run Haskell Dockerfile Linter"
task :hadolint do
  puts "Running Haskell Dockerfile Linter..."

  Open3.capture3("hadolint Dockerfile").then do |stdout, _stderr, status|
    status.success? ? puts("✓ No issues detected.") : abort(stdout)
  end
end

desc "Run code quality checks"
task quality: %i[git_lint rubocop hadolint]

task default: :quality
