# frozen_string_literal: true

require "test_helper"

class AnnotationTest < LangExtractTest
  def test_annotator_builds_annotated_document_with_document_ids_and_offsets
    document = LangExtract::Document.new(text: "Alice met Bob.", id: "doc")
    annotator = LangExtract::Core::Annotator.new

    annotated = annotator.annotate(
      document: document,
      extraction_hashes: [{ text: "Alice", extraction_class: "person" }]
    )

    assert_instance_of LangExtract::AnnotatedDocument, annotated
    assert_equal "doc", annotated.extractions.first.document_id
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 5), annotated.extractions.first.char_interval
  end
end
