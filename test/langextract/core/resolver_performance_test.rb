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
end
