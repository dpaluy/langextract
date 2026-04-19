# frozen_string_literal: true

require "test_helper"

class FormatHandlerTest < LangExtractTest
  def setup
    super
    @handler = LangExtract::Core::FormatHandler.new
  end

  def test_parses_fenced_json_and_normalizes_extraction_wrappers
    output = <<~TEXT
      Here is the result:
      ```json
      {"extractions":[{"text":"Alice","class":"person","attributes":{"age":30}}]}
      ```
    TEXT

    assert_equal(
      [
        {
          "extraction_class" => "person",
          "text" => "Alice",
          "description" => nil,
          "attributes" => { "age" => 30 },
          "group_id" => nil
        }
      ],
      @handler.parse(output)
    )
  end

  def test_parses_yaml_output
    output = <<~YAML
      extractions:
        - text: "$94.8 billion"
          extraction_class: revenue
    YAML

    assert_equal "$94.8 billion", @handler.parse(output, format: :yaml).first["text"]
  end

  def test_returns_empty_result_in_lenient_mode_when_parsing_fails
    assert_empty @handler.parse("not json", strict: false)
  end

  def test_raises_descriptive_parsing_error_in_strict_mode
    error = assert_raises(LangExtract::FormatParsingError) { @handler.parse("not json") }

    assert_match(/unable to parse/, error.message)
  end

  def test_validates_extractions_against_user_schema
    output = { extractions: [{ text: "Alice", extraction_class: "person" }] }.to_json
    schema = {
      required: %w[text extraction_class],
      properties: {
        text: { type: "string" },
        extraction_class: { type: "string" },
        attributes: { type: "object" }
      }
    }

    assert_equal "Alice", @handler.parse(output, schema: schema).first["text"]
  end

  def test_schema_validation_fails_for_missing_required_fields
    output = { extractions: [{ text: "Alice" }] }.to_json
    schema = { required: %w[text extraction_class] }

    error = assert_raises(LangExtract::FormatParsingError) { @handler.parse(output, schema: schema) }

    assert_match(/missing extraction_class/, error.message)
  end
end
