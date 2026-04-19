# frozen_string_literal: true

require_relative "lib/langextract/version"

Gem::Specification.new do |spec|
  spec.name = "langextract"
  spec.version = LangExtract::VERSION
  spec.authors = ["David Paluy"]
  spec.email = ["dpaluy@users.noreply.github.com"]

  spec.summary = "Ruby port of LangExtract for source-grounded structured extraction."
  spec.description = "Extract structured information from text with source grounding, deterministic serialization, " \
                     "and HTML visualization."
  spec.homepage = "https://github.com/dpaluy/langextract"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.5"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/langextract"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z --cached --others --exclude-standard], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |file|
      excluded = %w[
        .agents/ .github/ .gitignore .omx/ .ruby-lsp/ .ruby-version .rubocop.yml .tool-versions .yardopts
        AGENTS.md CLAUDE.md Gemfile Rakefile bin/ doc/ docs/ pkg/ spec/ test/
      ]

      (file == gemspec) || file.start_with?(*excluded)
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |file| File.basename(file) }
  spec.require_paths = ["lib"]
  spec.extra_rdoc_files = Dir["README.md", "CHANGELOG.md", "LICENSE.txt"]
end
