# frozen_string_literal: true

require "test_helper"

class DataTest < LangExtractTest
  def test_annotated_document_round_trips_deterministic_hashes_without_losing_extraction_fields
    document = LangExtract::Document.new(text: "Alice met Bob.", id: "doc-1", metadata: { source: "test" })
    extraction = LangExtract::Extraction.new(
      extraction_class: "person",
      text: "Alice",
      description: "person name",
      attributes: { role: "speaker" },
      char_interval: LangExtract::CharInterval.new(start_pos: 0, end_pos: 5),
      token_interval: LangExtract::TokenInterval.new(start_pos: 0, end_pos: 1),
      alignment_status: LangExtract::AlignmentStatus::EXACT,
      extraction_index: 0,
      group_id: "g1",
      document_id: "doc-1"
    )
    annotated = LangExtract::AnnotatedDocument.new(document: document, extractions: [extraction])

    loaded = LangExtract::AnnotatedDocument.from_h(JSON.parse(JSON.generate(annotated.to_h)))

    assert_equal annotated.to_h, loaded.to_h
  end

  def test_char_interval_requires_documented_serialized_keys
    assert_raises(ArgumentError) do
      LangExtract::CharInterval.from_h({ "start" => 1, "end" => 2 })
    end
  end

  def test_example_data_normalizes_extraction_objects_to_prompt_fields_only
    extraction = LangExtract::Extraction.new(
      text: "Alice",
      extraction_class: "person",
      char_interval: LangExtract::CharInterval.new(start_pos: 0, end_pos: 5),
      alignment_status: LangExtract::AlignmentStatus::EXACT
    )

    example = LangExtract::ExampleData.new(text: "Alice", extractions: [extraction])

    assert_equal(
      [
        {
          "extraction_class" => "person",
          "text" => "Alice",
          "description" => nil,
          "attributes" => {},
          "group_id" => nil
        }
      ],
      example.extractions
    )
  end

  def test_extraction_attributes_deep_freeze_nested_hashes
    extraction = LangExtract::Extraction.new(text: "Alice", attributes: { nested: { role: "before" } })

    assert_raises(FrozenError) { extraction.attributes["nested"]["role"] = "after" }
  end

  def test_extraction_attributes_deep_freeze_hashes_nested_in_arrays
    extraction = LangExtract::Extraction.new(text: "Alice", attributes: { roles: [{ name: "before" }] })

    assert_raises(FrozenError) { extraction.attributes["roles"][0]["name"] = "after" }
  end

  def test_document_metadata_deep_freezes_nested_hashes
    document = LangExtract::Document.new(text: "Alice", metadata: { nested: { source: "before" } })

    assert_raises(FrozenError) { document.metadata["nested"]["source"] = "after" }
  end
end
