# frozen_string_literal: true

require "test_helper"

class IOTest < LangExtractTest
  def test_saves_and_loads_jsonl_without_losing_annotated_document_data
    document = LangExtract::Document.new(text: "Alice met Bob.", id: "doc")
    annotated = LangExtract::AnnotatedDocument.new(
      document: document,
      extractions: [
        LangExtract::Extraction.new(
          text: "Alice",
          char_interval: LangExtract::CharInterval.new(start_pos: 0, end_pos: 5),
          alignment_status: LangExtract::AlignmentStatus::EXACT,
          document_id: "doc"
        )
      ]
    )

    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.jsonl")
      LangExtract::IO.save_annotated_documents(path, [annotated])

      assert_equal [annotated.to_h], LangExtract::IO.load_annotated_documents_jsonl(path).map(&:to_h)
    end
  end

  def test_save_wraps_file_system_failures
    Dir.mktmpdir do |dir|
      assert_raises(LangExtract::IOFailure) do
        LangExtract::IO.save_annotated_documents(dir, [])
      end
    end
  end
end
