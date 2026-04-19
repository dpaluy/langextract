# frozen_string_literal: true

require "test_helper"

class UpstreamParityTest < LangExtractTest
  def setup
    super
    path = File.expand_path("../fixtures/upstream/core_cases.json", __dir__)
    @fixtures = JSON.parse(File.read(path))
  end

  def test_matches_tokenizer_offset_fixtures
    @fixtures.fetch("tokenizer").each do |fixture|
      tokens = LangExtract::Core::UnicodeTokenizer.new.tokenize(fixture.fetch("input"))
      expected = fixture.fetch("tokens").map.with_index do |token, index|
        {
          "text" => token.fetch("text"),
          "char_interval" => {
            "start_pos" => token.fetch("start_pos"),
            "end_pos" => token.fetch("end_pos")
          },
          "index" => index
        }
      end

      assert_equal expected, tokens.map(&:to_h), fixture.fetch("name")
    end
  end

  def test_matches_resolver_alignment_fixtures
    @fixtures.fetch("resolver").each do |fixture|
      resolver = LangExtract::Core::Resolver.new(text: fixture.fetch("text"))
      extractions = resolver.resolve(fixture.fetch("extractions"))
      actual = extractions.map do |extraction|
        {
          "status" => extraction.alignment_status,
          "start_pos" => extraction.char_interval&.start_pos,
          "end_pos" => extraction.char_interval&.end_pos
        }
      end

      assert_equal fixture.fetch("expected"), actual, fixture.fetch("name")
    end
  end

  def test_matches_format_handler_fixtures
    @fixtures.fetch("format_handler").each do |fixture|
      parsed = LangExtract::Core::FormatHandler.new.parse(
        fixture.fetch("output"),
        format: fixture.fetch("format").to_sym
      )
      expected = fixture.fetch("expected")

      assert_equal expected, parsed.map { |item| item.slice("text", "extraction_class") }, fixture.fetch("name")
    end
  end

  def test_upstream_v1_2_1_manifest_captures_full_collected_test_surface
    path = File.expand_path("../fixtures/upstream/v1_2_1_pytest_manifest.json", __dir__)
    manifest = JSON.parse(File.read(path))

    assert_equal "v1.2.1", manifest.dig("upstream", "tag")
    assert_equal 419, manifest.dig("counts", "total")
    assert_equal 404, manifest.dig("counts", "deterministic")
    assert_equal 11, manifest.dig("counts", "live_api")
    assert_equal 4, manifest.dig("counts", "ollama_integration")
    assert_equal 82, manifest.dig("counts", "by_file", "tests/resolver_test.py")
    assert_equal 59, manifest.dig("counts", "by_file", "tests/tokenizer_test.py")
  end
end
