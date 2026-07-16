# frozen_string_literal: true

require_relative "data"
require_relative "fuzzy_alignment_index"
require_relative "fuzzy_alignment_planner"

module LangExtract
  module Core
    # Coordinates indexed ordered-subsequence fuzzy alignment and candidate
    # selection. Index construction and dynamic planning live separately.
    class FuzzyAligner
      # Historical limit retained for compatibility. Indexed planning no longer
      # truncates candidate starts.
      MAX_FUZZY_CANDIDATE_STARTS = 4_000
      SubsequenceAlignment = FuzzyAlignmentPlanner::SubsequenceAlignment

      def initialize(source_tokens:, fuzzy_threshold:, min_coverage:, min_density:, allow_overlaps:)
        @source_tokens = source_tokens
        @fuzzy_threshold = fuzzy_threshold
        @allow_overlaps = allow_overlaps
        @alignment_index = FuzzyAlignmentIndex.new(source_tokens)
        @planner = FuzzyAlignmentPlanner.new(
          source_tokens: source_tokens,
          alignment_index: alignment_index,
          fuzzy_threshold: fuzzy_threshold,
          min_coverage: min_coverage,
          min_density: min_density
        )
      end

      # Returns [CharInterval, score] candidates ranked by score, then position.
      def candidates(target_tokens, range, occupied)
        alignments = all_subsequence_alignments(target_tokens)
        return [] if alignments.empty?

        found = alignments.filter_map do |alignment|
          next unless planner.feasible?(alignment, target_tokens.length)

          interval = interval_for_alignment(alignment.token_indices, range)
          next unless interval

          match = [interval, alignment.score]
          return [match] if perfect_non_overlapping?(match, occupied)

          match
        end

        ranked_unique_candidates(found)
      end

      private

      attr_reader :source_tokens, :fuzzy_threshold, :allow_overlaps, :alignment_index, :planner

      def all_subsequence_alignments(target_tokens)
        start_flags = Array.new(source_tokens.length, false)
        target_tokens.each do |target_token|
          alignment_index.matching_positions(target_token).indices.each { |idx| start_flags[idx] = true }
        end
        valid_starts = start_flags.each_index.select { |idx| start_flags[idx] }
        return [] if valid_starts.empty?

        seen = {}
        valid_starts.each_with_object([]) do |start, alignments|
          alignment = align_from_start(target_tokens, start)
          next unless alignment
          next if seen[alignment.token_indices]

          seen[alignment.token_indices] = true
          alignments << alignment
        end
      end

      def align_from_start(target_tokens, source_start)
        planner.alignment_for(target_tokens, source_start)
      end

      def find_token_match(target_token, from_index)
        alignment_index.best_match(target_token, from_index)
      end

      def norm_source
        alignment_index.normalized_tokens
      end

      def interval_for_alignment(token_indices, range)
        return nil if token_indices.empty?

        first_token = source_tokens[token_indices.first]
        last_token = source_tokens[token_indices.last]
        start_pos = [first_token.char_interval.start_pos, range.begin].max
        end_pos = [last_token.char_interval.end_pos, range.end].min
        return nil if start_pos >= end_pos

        CharInterval.new(start_pos: start_pos, end_pos: end_pos)
      end

      def perfect_non_overlapping?(match, occupied)
        interval, score = match
        score >= 1.0 && (allow_overlaps || !overlaps_any?(interval, occupied))
      end

      def ranked_unique_candidates(candidates)
        best_by_interval = candidates.each_with_object({}) do |(interval, score), result|
          key = [interval.start_pos, interval.end_pos]
          result[key] = [interval, score] if result[key].nil? || score > result[key].last
        end

        best_by_interval.values.sort_by { |interval, score| [-score, interval.start_pos, interval.end_pos] }
      end

      def overlaps_any?(interval, occupied)
        occupied.any? { |other| interval.overlaps?(other) }
      end
    end
  end
end
