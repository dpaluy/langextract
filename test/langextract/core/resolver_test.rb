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

  def test_preferred_interval_exact_match_wins
    resolver = LangExtract::Core::Resolver.new(text: "Alice outside. Alice inside.")
    preferred = LangExtract::CharInterval.new(start_pos: 15, end_pos: 28)

    extraction = resolver.resolve([{ "text" => "Alice" }], preferred_interval: preferred).first

    assert_equal LangExtract::CharInterval.new(start_pos: 15, end_pos: 20), extraction.char_interval
  end

  def test_exact_alignment_falls_back_when_preferred_occurrence_is_occupied
    resolver = LangExtract::Core::Resolver.new(text: "Alice outside. Alice inside.")
    preferred = LangExtract::CharInterval.new(start_pos: 15, end_pos: 28)

    extractions = resolver.resolve([{ "text" => "Alice" }, { "text" => "Alice" }], preferred_interval: preferred)

    assert_equal([15, 0], extractions.map { |extraction| extraction.char_interval.start_pos })
    assert_equal [LangExtract::AlignmentStatus::EXACT] * 2, extractions.map(&:alignment_status)
  end

  def test_fuzzy_alignment_falls_back_when_preferred_occurrence_is_occupied
    text = "Jonathon Smith outside. Jonathon Smith inside."
    resolver = LangExtract::Core::Resolver.new(text: text)
    preferred = LangExtract::CharInterval.new(start_pos: 24, end_pos: text.length)

    extractions = resolver.resolve(
      [{ "text" => "Jonathan Smith" }, { "text" => "Jonathan Smith" }],
      preferred_interval: preferred
    )

    assert_equal([24, 0], extractions.map { |extraction| extraction.char_interval.start_pos })
    assert_equal [LangExtract::AlignmentStatus::FUZZY] * 2, extractions.map(&:alignment_status)
  end

  def test_fuzzy_early_exit_returns_earliest_normalized_equal_match
    text = "Alpha   Beta then Alpha   Beta"
    resolver = LangExtract::Core::Resolver.new(text: text)

    target = "alpha beta"
    candidates = resolver.send(
      :fuzzy_candidates_in_range,
      "Alpha Beta",
      target,
      target.each_char.tally,
      0...text.length,
      []
    )

    assert_equal 1, candidates.length
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 12), candidates.first.first
    assert_equal 1.0, candidates.first.last
  end

  def test_fuzzy_early_exit_skips_occupied_perfect_match
    text = "Alpha   Beta then Alpha   Beta"
    resolver = LangExtract::Core::Resolver.new(text: text)

    extractions = resolver.resolve([{ "text" => "Alpha Beta" }, { "text" => "Alpha Beta" }])

    assert_equal [LangExtract::AlignmentStatus::FUZZY] * 2, extractions.map(&:alignment_status)
    assert_equal(
      [
        LangExtract::CharInterval.new(start_pos: 0, end_pos: 12),
        LangExtract::CharInterval.new(start_pos: 18, end_pos: 30)
      ],
      extractions.map(&:char_interval)
    )
  end

  def test_similarity_matches_sequence_matcher_ratio
    resolver = LangExtract::Core::Resolver.new(text: "placeholder")

    assert_in_delta 0.75, resolver.send(:similarity, "abcd", "bcde"), 0.0001
  end
end
