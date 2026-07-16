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

  def test_fuzzy_formatting_normalization_is_symmetric
    [
      ["New-York office", "New York", 0, 8],
      ["New York office", "New-York", 0, 8],
      ["Smith, John", "Smith John", 0, 11],
      ["Smith John", "Smith, John", 0, 10],
      ["total 1,000 units", "1 000", 6, 11],
      ["total 1 000 units", "1,000", 6, 11],
      ["don't stop", "dont", 0, 5],
      ["dont stop", "don't", 0, 4]
    ].each do |source, target, start_pos, end_pos|
      extraction = LangExtract::Core::Resolver.new(text: source).resolve([{ "text" => target }]).first

      assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status,
                   "expected #{target.inspect} to ground in #{source.inspect}"
      assert_equal LangExtract::CharInterval.new(start_pos: start_pos, end_pos: end_pos), extraction.char_interval
    end
  end

  def test_fuzzy_requires_target_negation_to_be_present_in_source
    resolver = LangExtract::Core::Resolver.new(text: "evidence of disease")
    extraction = resolver.resolve([{ "text" => "no evidence of disease" }]).first

    assert_equal LangExtract::AlignmentStatus::UNGROUNDED, extraction.alignment_status
    assert_nil extraction.char_interval
  end

  def test_fuzzy_requires_target_negation_to_match_an_equivalent_source_token
    resolver = LangExtract::Core::Resolver.new(text: "fever evidence")
    extraction = resolver.resolve([{ "text" => "never evidence" }]).first

    assert_equal LangExtract::AlignmentStatus::UNGROUNDED, extraction.alignment_status
    assert_nil extraction.char_interval
  end

  def test_fuzzy_allows_short_typo_when_another_token_is_exact
    resolver = LangExtract::Core::Resolver.new(text: "Jon Smith signed")
    extraction = resolver.resolve([{ "text" => "John Smith" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 9), extraction.char_interval
  end

  def test_fuzzy_short_typo_is_unicode_safe_when_anchored
    resolver = LangExtract::Core::Resolver.new(text: "cafe noir")
    extraction = resolver.resolve([{ "text" => "café noir" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 9), extraction.char_interval
  end

  def test_fuzzy_does_not_relax_one_or_two_character_tokens
    resolver = LangExtract::Core::Resolver.new(text: "b exact")
    extraction = resolver.resolve([{ "text" => "a exact" }]).first

    assert_equal LangExtract::AlignmentStatus::UNGROUNDED, extraction.alignment_status
    assert_nil extraction.char_interval
  end

  def test_fuzzy_accepts_density_at_the_default_boundary
    resolver = LangExtract::Core::Resolver.new(text: "a x y b")
    extraction = resolver.resolve([{ "text" => "a b" }]).first

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 7), extraction.char_interval
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
