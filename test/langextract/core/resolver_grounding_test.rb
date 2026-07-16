# frozen_string_literal: true

require "test_helper"

class ResolverGroundingTest < LangExtractTest
  def test_fuzzy_does_not_bridge_sentence_boundaries
    resolver = LangExtract::Core::Resolver.new(text: "Alice left. Cancer affected Bob.")
    extraction = resolver.resolve([{ "text" => "Alice cancer" }]).first

    assert_equal LangExtract::AlignmentStatus::UNGROUNDED, extraction.alignment_status
    assert_nil extraction.char_interval
  end

  def test_fuzzy_does_not_hide_negation_between_matched_tokens
    resolver = LangExtract::Core::Resolver.new(text: "Alice denies cancer")
    extraction = resolver.resolve([{ "text" => "Alice cancer" }]).first

    assert_equal LangExtract::AlignmentStatus::UNGROUNDED, extraction.alignment_status
    assert_nil extraction.char_interval
  end

  def test_fuzzy_accepts_punctuation_boundary_variant
    resolver = LangExtract::Core::Resolver.new(text: "New-York office")
    extraction = resolver.resolve([{ "text" => "New York" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 8), extraction.char_interval
  end

  def test_fuzzy_min_coverage_allows_three_of_four_target_tokens
    resolver = LangExtract::Core::Resolver.new(text: "Jonathan Smith signed")
    extraction = resolver.resolve([{ "text" => "Jonathan Smith quickly signed" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 21), extraction.char_interval
  end

  def test_fuzzy_min_coverage_allows_missing_leading_target_token
    resolver = LangExtract::Core::Resolver.new(text: "Jonathan Smith signed and quickly")
    extraction = resolver.resolve([{ "text" => "quickly Jonathan Smith signed" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 21), extraction.char_interval
  end

  def test_fuzzy_min_coverage_rejects_two_of_three_target_tokens
    resolver = LangExtract::Core::Resolver.new(text: "Jonathan Smith signed")
    extraction = resolver.resolve([{ "text" => "Jonathan quickly signed" }]).first

    assert_equal LangExtract::AlignmentStatus::UNGROUNDED, extraction.alignment_status
    assert_nil extraction.char_interval
  end

  def test_fuzzy_prefers_later_exact_token_at_strict_threshold
    resolver = LangExtract::Core::Resolver.new(
      text: "alpha Jonathen Jonathan",
      fuzzy_threshold: 0.99
    )
    extraction = resolver.resolve([{ "text" => "alpha Jonathan" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 23), extraction.char_interval
  end

  def test_fuzzy_keeps_earlier_similar_token_when_it_preserves_global_path
    text = "alpha Jonathen beta Jonathan"
    resolver = LangExtract::Core::Resolver.new(text: text)
    extraction = resolver.resolve([{ "text" => "alpha Jonathan beta" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 19), extraction.char_interval
  end

  def test_fuzzy_prefers_high_score_partial_path_over_low_score_full_path
    resolver = LangExtract::Core::Resolver.new(
      text: "alpha brxvo charlie delta",
      fuzzy_threshold: 0.99
    )
    extraction = resolver.resolve([{ "text" => "alpha bravo charlie delta" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 25), extraction.char_interval
  end

  def test_fuzzy_does_not_choose_later_exact_token_across_negation_barrier
    resolver = LangExtract::Core::Resolver.new(text: "alpha brxvo not bravo")
    extraction = resolver.resolve([{ "text" => "alpha bravo" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 11), extraction.char_interval
  end

  def test_fuzzy_keeps_compact_lower_score_path_over_sparse_exact_path
    resolver = LangExtract::Core::Resolver.new(text: "alpha brxvo gap gap gap bravo")
    extraction = resolver.resolve([{ "text" => "alpha bravo" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 11), extraction.char_interval
  end
end
