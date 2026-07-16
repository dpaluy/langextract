# frozen_string_literal: true

require "test_helper"

# Performance benchmark for the fuzzy aligner indexed lookup (issue #9).
# Runs the exact reproduction case that was 115x slower than master and
# asserts a hard wall-clock ceiling. Guarded by FUZZY_PERF_TEST env var so
# CI can opt in; the deterministic invocation-count guard in resolver_test.rb
# is the primary gate.
class ResolverPerformanceTest < LangExtractTest
  def test_4000_repeated_starts_completes_under_one_second
    skip "Set FUZZY_PERF_TEST=1 to run performance benchmark" unless ENV["FUZZY_PERF_TEST"]

    # Exact reproduction input from PR #14 review: 4001 source tokens,
    # 4000 valid starts, 2-token target.
    text = "#{'jonathon ' * 4000}smith"
    target = "Jonathan Smith"

    resolver = LangExtract::Core::Resolver.new(text: text)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    extraction = resolver.resolve([{ "text" => target }]).first
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    assert_equal LangExtract::AlignmentStatus::FUZZY, extraction.alignment_status
    assert elapsed < 1.0,
           "fuzzy alignment of 4000-start document took #{elapsed.round(3)}s, expected < 1.0s"
  end

  def test_large_sparse_source_keeps_late_candidates_for_multiple_items
    text = "#{'filler ' * 12_000}Jonathon Smith and Alpa Beta"
    resolver = LangExtract::Core::Resolver.new(text: text)

    extractions = resolver.resolve(
      [
        { "text" => "Jonathan Smith" },
        { "text" => "Alpha Beta" }
      ]
    )

    assert_equal [LangExtract::AlignmentStatus::FUZZY, LangExtract::AlignmentStatus::FUZZY],
                 extractions.map(&:alignment_status)
    assert_equal text.index("Jonathon Smith"), extractions.first.char_interval.start_pos
    assert_equal text.index("Alpa Beta"), extractions.last.char_interval.start_pos
  end

  def test_oversized_range_skips_fuzzy_planning_without_affecting_exact_alignment
    cap = LangExtract::Core::Resolver::MAX_FUZZY_RANGE_TOKENS
    text = "#{'filler ' * (cap + 1)}Jonathon Smith"
    resolver = LangExtract::Core::Resolver.new(text: text)

    fuzzy = resolver.resolve([{ "text" => "Jonathan Smith" }]).first
    exact = resolver.resolve([{ "text" => "Jonathon Smith" }]).first

    assert_equal LangExtract::AlignmentStatus::UNGROUNDED, fuzzy.alignment_status
    assert_equal LangExtract::AlignmentStatus::EXACT, exact.alignment_status
    assert_equal text.index("Jonathon Smith"), exact.char_interval.start_pos
  end
end
