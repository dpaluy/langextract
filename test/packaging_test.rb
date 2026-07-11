# frozen_string_literal: true

require "test_helper"

class PackagingTest < LangExtractTest
  def test_gemspec_ships_only_tracked_runtime_files
    spec = Gem::Specification.load("langextract.gemspec")
    tracked_files = `git ls-files --cached`.split("\n")

    assert(spec.files.all? { |file| tracked_files.include?(file) })
    assert_includes spec.files, "lib/langextract.rb"
    refute(spec.files.any? { |file| file.start_with?("test/", "spec/", "pkg/") })
  end
end
