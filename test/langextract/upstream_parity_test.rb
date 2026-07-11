# frozen_string_literal: true

require "test_helper"

class UpstreamParityTest < LangExtractTest
  def setup
    super
    path = File.expand_path("../fixtures/upstream/core_cases.json", __dir__)
    @fixtures = JSON.parse(File.read(path, encoding: "UTF-8"))
  end

  def test_executes_each_mapped_upstream_v1_2_1_tokenizer_case
    @fixtures.fetch("tokenizer_parity").fetch("cases").each do |fixture|
      fixture.fetch("scenarios").each do |scenario|
        actual = LangExtract::Core::UnicodeTokenizer.new.tokenize(scenario.fetch("input")).map(&:to_h)
        expected = scenario.fetch("tokens").map.with_index do |token, index|
          {
            "text" => token.fetch("text"),
            "char_interval" => {
              "start_pos" => token.fetch("start_pos"),
              "end_pos" => token.fetch("end_pos")
            },
            "index" => index
          }
        end

        assert_equal expected, actual, "#{fixture.fetch('upstream_id')}: #{scenario.fetch('name')}"
      end
    end
  end

  def test_maps_every_upstream_tokenizer_node_to_executable_coverage_or_exclusion
    tokenizer = @fixtures.fetch("tokenizer_parity")

    assert_tokenizer_provenance(tokenizer)
    assert_equal tokenizer_manifest_ids.sort, tokenizer_coverage_ids(tokenizer).sort
    assert_equal 59, tokenizer_coverage_ids(tokenizer).length
    assert tokenizer_exclusion_reasons_present?(tokenizer)
  end

  def test_matches_resolver_alignment_fixtures
    parity = @fixtures.fetch("resolver_parity")

    assert_equal "v1.2.1", parity.dig("provenance", "tag")
    assert_equal "9cd220c14ec6dbb64ba00b710bd376ffd17f1d29", parity.dig("provenance", "commit")
    assert_upstream_resolver_node_ids_are_mapped(parity)
    assert_resolver_alignment_cases(@fixtures.fetch("resolver"))
    assert_resolver_alignment_cases(parity.fetch("cases"))
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
    manifest = JSON.parse(File.read(path, encoding: "UTF-8"))

    assert_equal "v1.2.1", manifest.dig("upstream", "tag")
    assert_equal 419, manifest.dig("counts", "total")
    assert_equal 404, manifest.dig("counts", "deterministic")
    assert_equal 11, manifest.dig("counts", "live_api")
    assert_equal 4, manifest.dig("counts", "ollama_integration")
    assert_equal 82, manifest.dig("counts", "by_file", "tests/resolver_test.py")
    assert_equal 59, manifest.dig("counts", "by_file", "tests/tokenizer_test.py")
  end

  private

  def assert_upstream_resolver_node_ids_are_mapped(parity)
    upstream_node_ids = upstream_resolver_node_ids
    mapped_node_ids = parity.fetch("cases").flat_map { |fixture| fixture.fetch("upstream_node_ids") }
    mapped_node_ids.concat(parity.fetch("unsupported_cases").map { |fixture| fixture.fetch("upstream_node_id") })

    assert_equal upstream_node_ids.sort, mapped_node_ids.sort
    assert_equal mapped_node_ids.length, mapped_node_ids.uniq.length
  end

  def assert_resolver_alignment_cases(fixtures)
    fixtures.each do |fixture|
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

  def upstream_resolver_node_ids
    path = File.expand_path("../fixtures/upstream/v1_2_1_pytest_manifest.json", __dir__)
    manifest = JSON.parse(File.read(path, encoding: "UTF-8"))

    manifest.fetch("tests").filter_map do |test|
      test.fetch("id") if test.fetch("file") == "tests/resolver_test.py"
    end
  end
  def tokenizer_manifest_ids
    manifest.fetch("tests").filter_map do |test|
      test.fetch("id") if test.fetch("file") == "tests/tokenizer_test.py"
    end
  end

  def manifest
    path = File.expand_path("../fixtures/upstream/v1_2_1_pytest_manifest.json", __dir__)
    JSON.parse(File.read(path, encoding: "UTF-8"))
  end

  def assert_tokenizer_provenance(tokenizer)
    assert_equal "v1.2.1", tokenizer.dig("upstream", "tag")
    assert_equal "9cd220c14ec6dbb64ba00b710bd376ffd17f1d29", tokenizer.dig("upstream", "commit")
  end

  def tokenizer_coverage_ids(tokenizer)
    cases = tokenizer.fetch("cases")
    exclusions = tokenizer.fetch("exclusions")
    ids = (cases + exclusions).map { |fixture| fixture.fetch("upstream_id") }

    assert_equal ids.length, ids.uniq.length
    ids
  end

  def tokenizer_exclusion_reasons_present?(tokenizer)
    tokenizer.fetch("exclusions").all? { |fixture| fixture.fetch("reason").length.positive? }
  end
end
