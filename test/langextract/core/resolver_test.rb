# frozen_string_literal: true

require "test_helper"

class ResolverTest < LangExtractTest
  def test_aligns_exact_extraction_text_and_token_offsets
    resolver = LangExtract::Core::Resolver.new(text: "Alice met Bob.")
    extraction = resolver.resolve([{ "text" => "Bob", "extraction_class" => "person" }], document_id: "doc").first

    assert_equal LangExtract::AlignmentStatus::EXACT, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 10, end_pos: 13), extraction.char_interval
    assert_equal LangExtract::TokenInterval.new(start_pos: 2, end_pos: 3), extraction.token_interval
  end

  def test_uses_fuzzy_alignment_for_near_matches
    resolver = LangExtract::Core::Resolver.new(text: "Jonathan Smith signed the contract.")
    extraction = resolver.resolve([{ "text" => "Jonathon Smith" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal 0, extraction.char_interval.start_pos
  end

  def test_uses_next_best_non_overlapping_fuzzy_span_for_repeated_near_matches
    resolver = LangExtract::Core::Resolver.new(text: "Jonathon Smith met Jonathon Smith.")
    extractions = resolver.resolve([{ "text" => "Jonathan Smith" }, { "text" => "Jonathan Smith" }])

    assert_equal(
      [LangExtract::AlignmentStatus::FUZZY, LangExtract::AlignmentStatus::FUZZY],
      extractions.map(&:alignment_status)
    )
    assert_equal(
      [
        LangExtract::CharInterval.new(start_pos: 0, end_pos: 14),
        LangExtract::CharInterval.new(start_pos: 19, end_pos: 33)
      ],
      extractions.map(&:char_interval)
    )
  end

  def test_marks_duplicate_overlapping_spans_instead_of_silently_returning_both_as_exact
    resolver = LangExtract::Core::Resolver.new(text: "Alice met Bob.")
    extractions = resolver.resolve([{ "text" => "Alice" }, { "text" => "Alice" }])

    assert_equal(
      [LangExtract::AlignmentStatus::EXACT, LangExtract::AlignmentStatus::OVERLAP],
      extractions.map(&:alignment_status)
    )
  end

  def test_allows_overlapping_spans_when_configured
    resolver = LangExtract::Core::Resolver.new(text: "Alice met Bob.", allow_overlaps: true)
    extractions = resolver.resolve([{ "text" => "Alice" }, { "text" => "Alice met" }])

    assert_equal(
      [LangExtract::AlignmentStatus::EXACT, LangExtract::AlignmentStatus::EXACT],
      extractions.map(&:alignment_status)
    )
  end

  def test_represents_ungrounded_extractions_when_suppression_is_enabled
    resolver = LangExtract::Core::Resolver.new(text: "Alice met Bob.", suppress_alignment_errors: true)
    extraction = resolver.resolve([{ "text" => "Charlie" }]).first

    assert_equal LangExtract::AlignmentStatus::UNGROUNDED, extraction.alignment_status
    assert_nil extraction.char_interval
  end

  def test_raises_alignment_errors_when_suppression_is_disabled
    resolver = LangExtract::Core::Resolver.new(text: "Alice met Bob.", suppress_alignment_errors: false)

    assert_raises(LangExtract::AlignmentError) { resolver.resolve([{ "text" => "Charlie" }]) }
  end

  def test_fuzzy_alignment_searches_token_starts_on_long_documents
    text = "#{'filler ' * 1_000}Jonathon Smith"
    resolver = LangExtract::Core::Resolver.new(text: text)
    extraction = resolver.resolve([{ "text" => "Jonathan Smith" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal text.index("Jonathon Smith"), extraction.char_interval.start_pos
  end

  def test_similarity_matches_sequence_matcher_ratio
    resolver = LangExtract::Core::Resolver.new(text: "placeholder")

    assert_in_delta 0.75, resolver.send(:similarity, "abcd", "bcde"), 0.0001
  end
end
