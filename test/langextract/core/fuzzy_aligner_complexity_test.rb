# frozen_string_literal: true

require "test_helper"

# Deterministic complexity and behavioral equivalence tests for the
# FuzzyAligner indexed lookup (issue #9 review). These tests are
# wall-clock-independent: they assert bounds on the number of
# TokenSimilarity.similar? invocations and verify the all-or-nothing
# alignment semantics.
class FuzzyAlignerComplexityTest < LangExtractTest
  # --- Deterministic invocation-count complexity guard ---

  def test_similar_invocations_bounded_on_4000_repeated_starts
    # Exact reproduction case: 4001 source tokens, 4000 valid starts, 2-token
    # target. On the old O(N²) code this called similar? ~8M times. The
    # indexed approach bounds the call count to O(N).
    text = "#{'jonathon ' * 4000}smith"
    resolver = LangExtract::Core::Resolver.new(text: text)
    source_tokens = resolver.send(:tokens)
    target_tokens = %w[jonathon smith]

    call_count = count_similar_calls do
      aligner = LangExtract::Core::FuzzyAligner.new(
        source_tokens: source_tokens,
        fuzzy_threshold: 0.78,
        min_coverage: 0.70,
        min_density: 0.34,
        allow_overlaps: false
      )
      aligner.send(:all_subsequence_alignments, target_tokens)
    end

    max_calls = 3 * source_tokens.length
    assert call_count < max_calls,
           "expected similar? call count < #{max_calls} (3N) for #{source_tokens.length} tokens, got #{call_count}"
  end

  def test_char_similarity_does_not_scale_with_distinct_matches_per_start
    # Four thousand distinct texts can all pass the per-token similarity
    # floor. The score for each text should be computed once per target token,
    # rather than once for every candidate start (the old implementation was
    # quadratic in this shape).
    prefix = "abcdefghijklm"
    target = "abcdefghijklmnop"
    source_text = (0...4_000).map { |index| prefix + index.to_s(36).rjust(3, "0") }.join(" ")
    resolver = LangExtract::Core::Resolver.new(text: source_text)
    source_tokens = resolver.send(:tokens)
    target_tokens = Array.new(10, target)

    call_count = count_char_similarity_calls do
      aligner = LangExtract::Core::FuzzyAligner.new(
        source_tokens: source_tokens,
        fuzzy_threshold: 0.78,
        min_coverage: 0.70,
        min_density: 0.34,
        allow_overlaps: false
      )
      alignments = aligner.send(:all_subsequence_alignments, target_tokens)
      assert_operator alignments.length, :>, 0
      assert alignments.any? { |alignment| alignment.token_indices.last == 3_999 },
             "expected a path reaching the final source token"
    end

    max_calls = 2 * source_tokens.length * target_tokens.length
    message = "expected one similarity score per distinct text and target " \
              "(<= #{max_calls}), got #{call_count}"
    assert_operator call_count, :<=, max_calls, message
  end

  # --- Partial target matches feed the min_coverage gate ---

  def test_align_from_start_tracks_partial_matches_for_coverage
    resolver = LangExtract::Core::Resolver.new(text: "jonathon is here")
    aligner = LangExtract::Core::FuzzyAligner.new(
      source_tokens: resolver.send(:tokens),
      fuzzy_threshold: 0.78,
      min_coverage: 0.70,
      min_density: 0.34,
      allow_overlaps: false
    )

    # "smith" does not appear in the source; retain the matched token so the
    # candidate can apply the configured coverage threshold.
    result = aligner.send(:align_from_start, %w[jonathon smith], 0)
    assert_equal 1, result.matched
    assert_equal [0], result.token_indices
  end

  # --- Behavioral equivalence: indexed lookup produces correct results ---

  def test_indexed_lookup_finds_earliest_match_per_token
    # Source: alpha beta gamma alpha beta gamma
    # Target: alpha gamma → indices [0, 2]
    text = "alpha beta gamma alpha beta gamma"
    resolver = LangExtract::Core::Resolver.new(text: text)
    aligner = LangExtract::Core::FuzzyAligner.new(
      source_tokens: resolver.send(:tokens),
      fuzzy_threshold: 0.78,
      min_coverage: 0.70,
      min_density: 0.34,
      allow_overlaps: false
    )

    result = aligner.send(:align_from_start, %w[alpha gamma], 0)
    assert_equal [0, 2], result.token_indices
    assert_equal 1.0, result.score
  end

  def test_indexed_lookup_advances_from_index
    # Verifies find_token_match respects from_index, finding the second
    # occurrence of the token rather than the first.
    text = "alpha alpha beta"
    resolver = LangExtract::Core::Resolver.new(text: text)
    aligner = LangExtract::Core::FuzzyAligner.new(
      source_tokens: resolver.send(:tokens),
      fuzzy_threshold: 0.78,
      min_coverage: 0.70,
      min_density: 0.34,
      allow_overlaps: false
    )

    idx = aligner.send(:find_token_match, "alpha", 1)
    assert_equal 1, idx
  end

  def test_dense_similarity_matrix_preserves_highest_scoring_global_path
    target_tokens = %w[
      abcdefghijklmebd abcdefghijklmddc
      abcdefghijklmbde abcdefghijklmcde
    ]
    source_text = %w[
      abcdefghijklmbfe abcdefghijklmaef abcdefghijklmfbf abcdefghijklmbeb
      abcdefghijklmefa abcdefghijklmbaa abcdefghijklmeae abcdefghijklmcdb
    ].join(" ")
    source_tokens = LangExtract::Core::Resolver.new(text: source_text).send(:tokens)
    index = LangExtract::Core::FuzzyAlignmentIndex.new(source_tokens)
    planner = LangExtract::Core::FuzzyAlignmentPlanner.new(
      source_tokens: source_tokens,
      alignment_index: index,
      fuzzy_threshold: 0.78,
      min_coverage: 0.70,
      min_density: 0.50
    )

    alignment = planner.alignment_for(target_tokens, 0)

    assert_equal [0, 1, 3, 7], alignment.token_indices
    assert_in_delta 0.890625, alignment.score
  end

  private

  # Count TokenSimilarity.similar? invocations by wrapping the method.
  # Deterministic and wall-clock-independent.
  def count_similar_calls
    mod = LangExtract::Core::TokenSimilarity
    original = mod.method(:similar?)
    call_count = 0

    verbose = $VERBOSE
    $VERBOSE = nil
    begin
      mod.singleton_class.alias_method(:__similar_original__, :similar?)
      mod.singleton_class.define_method(:similar?) do |target, source|
        call_count += 1
        original.call(target, source)
      end

      yield
      call_count
    ensure
      mod.singleton_class.alias_method(:similar?, :__similar_original__)
      mod.singleton_class.remove_method(:__similar_original__)
      $VERBOSE = verbose
    end
  end

  def count_char_similarity_calls
    mod = LangExtract::Core::TokenSimilarity
    original = mod.method(:char_similarity)
    call_count = 0

    verbose = $VERBOSE
    $VERBOSE = nil
    begin
      mod.singleton_class.alias_method(:__char_similarity_original__, :char_similarity)
      mod.singleton_class.define_method(:char_similarity) do |left, right|
        call_count += 1
        original.call(left, right)
      end

      yield
      call_count
    ensure
      mod.singleton_class.alias_method(:char_similarity, :__char_similarity_original__)
      mod.singleton_class.remove_method(:__char_similarity_original__)
      $VERBOSE = verbose
    end
  end
end
