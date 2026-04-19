# frozen_string_literal: true

require "test_helper"

class ChunkingTest < LangExtractTest
  def test_chunks_on_sentence_boundaries_while_preserving_source_offsets
    document = LangExtract::Document.new(text: "First sentence. Second sentence. Third.", id: "doc")
    chunks = LangExtract::Core::SentenceAwareChunker.new(max_char_buffer: 20).chunks(document)

    assert_equal ["First sentence. ", "Second sentence. ", "Third."], chunks.map(&:text)
    assert_equal(
      [
        { "start_pos" => 0, "end_pos" => 16 },
        { "start_pos" => 16, "end_pos" => 33 },
        { "start_pos" => 33, "end_pos" => 39 }
      ],
      chunks.map { |chunk| chunk.char_interval.to_h }
    )
  end

  def test_splits_oversized_single_sentence_on_buffer_boundary
    document = LangExtract::Document.new(text: "Alpha beta gamma delta epsilon.", id: "doc")
    chunks = LangExtract::Core::SentenceAwareChunker.new(max_char_buffer: 12).chunks(document)

    assert_operator chunks.length, :>, 1
    assert(chunks.all? { |chunk| chunk.text.length <= 12 })
    assert_equal document.text, chunks.map(&:text).join
  end

  def test_sentence_boundaries_include_closing_quotes
    document = LangExtract::Document.new(text: "\"Hello.\" Next sentence.", id: "doc")
    chunks = LangExtract::Core::SentenceAwareChunker.new(max_char_buffer: 20).chunks(document)

    assert_equal ["\"Hello.\" ", "Next sentence."], chunks.map(&:text)
  end
end
