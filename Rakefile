# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

Minitest::TestTask.create
RuboCop::RakeTask.new(:rubocop)

begin
  require "yard"
  YARD::Rake::YardocTask.new
rescue LoadError
  # YARD is optional outside the development bundle.
end

task default: %i[test rubocop]
