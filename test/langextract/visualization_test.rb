# frozen_string_literal: true

require "test_helper"

class VisualizationTest < LangExtractTest
  def test_renders_self_contained_html_with_highlighted_grounded_spans
    document = LangExtract::Document.new(text: "Alice < Bob", id: "doc")
    annotated = LangExtract::AnnotatedDocument.new(
      document: document,
      extractions: [
        LangExtract::Extraction.new(
          text: "Alice",
          description: "person",
          char_interval: LangExtract::CharInterval.new(start_pos: 0, end_pos: 5),
          alignment_status: LangExtract::AlignmentStatus::EXACT
        )
      ]
    )

    html = LangExtract::Visualization.new.render(annotated)

    assert_includes html, "<!doctype html>"
    assert_includes html, "<mark"
    assert_includes html, "Alice"
    assert_includes html, "&lt;"
  end

  def test_escapes_extraction_labels
    document = LangExtract::Document.new(text: "Alice", id: "doc")
    annotated = LangExtract::AnnotatedDocument.new(
      document: document,
      extractions: [
        LangExtract::Extraction.new(
          text: "Alice",
          description: "<script>alert(1)</script>",
          char_interval: LangExtract::CharInterval.new(start_pos: 0, end_pos: 5),
          alignment_status: LangExtract::AlignmentStatus::EXACT
        )
      ]
    )

    html = LangExtract::Visualization.new.render(annotated)

    refute_includes html, "<script>"
    assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  def test_renders_in_memory_document_collections
    documents = [
      LangExtract::AnnotatedDocument.new(
        document: LangExtract::Document.new(text: "Alice", id: "doc-1"),
        extractions: [
          LangExtract::Extraction.new(
            text: "Alice",
            char_interval: LangExtract::CharInterval.new(start_pos: 0, end_pos: 5),
            alignment_status: LangExtract::AlignmentStatus::EXACT
          )
        ]
      ),
      LangExtract::AnnotatedDocument.new(
        document: LangExtract::Document.new(text: "Bob", id: "doc-2"),
        extractions: []
      )
    ]

    html = LangExtract::Visualization.new.render(documents)

    assert_includes html, "doc-1"
    assert_includes html, "doc-2"
    assert_includes html, "<mark"
  end

  def test_renders_every_document_from_jsonl_file
    documents = [
      LangExtract::AnnotatedDocument.new(document: LangExtract::Document.new(text: "Alice", id: "doc-1")),
      LangExtract::AnnotatedDocument.new(document: LangExtract::Document.new(text: "Bob", id: "doc-2"))
    ]

    Dir.mktmpdir do |dir|
      path = File.join(dir, "documents.jsonl")
      LangExtract::IO.save_annotated_documents(path, documents)

      html = LangExtract::Visualization.new.render(path)

      assert_includes html, "doc-1"
      assert_includes html, "doc-2"
    end
  end
end
