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

  # --- All-or-nothing: align_from_start must return nil if any token is unfound ---

  def test_align_from_start_returns_nil_when_any_target_token_unfound
    resolver = LangExtract::Core::Resolver.new(text: "jonathon is here")
    aligner = LangExtract::Core::FuzzyAligner.new(
      source_tokens: resolver.send(:tokens),
      fuzzy_threshold: 0.78,
      min_coverage: 0.70,
      min_density: 0.34,
      allow_overlaps: false
    )

    # "smith" does not appear in the source; align_from_start must return nil.
    result = aligner.send(:align_from_start, %w[jonathon smith], 0)
    assert_nil result
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
end
