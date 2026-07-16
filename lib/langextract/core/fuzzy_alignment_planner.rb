# frozen_string_literal: true

require_relative "token_similarity"

module LangExtract
  module Core
    # Plans ordered fuzzy token alignments with coverage, density, score, and
    # semantic-barrier constraints. The suffix table is shared by all starts.
    class FuzzyAlignmentPlanner
      MAX_PATH_ALTERNATIVES_PER_MATCH_COUNT = 2
      SENTENCE_BOUNDARY_PUNCTUATION = /[.!?\u2026\u3002\uff01\uff1f]/u
      NEGATION_TOKENS = %w[
        cannot can't can’t deny denies denied denying
        no not none neither never without
      ].freeze

      SubsequenceAlignment = Data.define(:matched, :window_size, :token_indices, :score)
      AlignmentPath = Data.define(:matched, :score_sum, :first_idx, :last_idx, :previous, :safe_gap)

      def initialize(source_tokens:, alignment_index:, fuzzy_threshold:, min_coverage:, min_density:)
        @source_tokens = source_tokens
        @alignment_index = alignment_index
        @fuzzy_threshold = fuzzy_threshold
        @min_coverage = min_coverage
        @min_density = min_density
      end

      def alignment_for(target_tokens, source_start)
        paths = alignment_table(target_tokens)[source_start]
        preferred_path(paths, target_tokens.length)
      end

      def feasible?(alignment, target_count)
        return false if target_count.zero?

        coverage = alignment.matched.to_f / target_count
        density = alignment.matched.to_f / alignment.window_size

        coverage >= min_coverage &&
          density >= min_density &&
          alignment.score >= fuzzy_threshold &&
          safe_source_gap?(alignment.token_indices)
      end

      private

      attr_reader :source_tokens, :alignment_index, :fuzzy_threshold, :min_coverage, :min_density

      def alignment_table(target_tokens)
        @alignment_table_cache ||= {}
        key = target_tokens.map(&:to_s).freeze
        @alignment_table_cache[key] ||= build_alignment_table(target_tokens)
      end

      def build_alignment_table(target_tokens)
        next_row = Array.new(source_tokens.length + 1) { [] }
        target_tokens.reverse_each do |target_token|
          next_row = alignment_row(target_token, next_row)
        end
        next_row
      end

      def alignment_row(target_token, next_row)
        matching = alignment_index.matching_positions(target_token)
        options = alignment_options(matching, next_row)
        best_match = suffix_best_paths(options)
        row = Array.new(source_tokens.length + 1)
        source_tokens.length.downto(0) do |source_position|
          row[source_position] = merge_path_frontiers(best_match[source_position], next_row[source_position])
        end
        row
      end

      def alignment_options(matching, next_row)
        matching.indices.each_with_index.flat_map do |idx, position|
          suffixes = next_row[idx + 1]
          base = path_with_match(idx, matching.scores[position], nil)
          continuations = suffixes.to_a.flat_map do |suffixes_for_count|
            next [] unless suffixes_for_count

            suffixes_for_count.filter_map do |suffix|
              next unless suffix.safe_gap && source_gap_safe?(idx, suffix.first_idx)

              path_with_match(idx, matching.scores[position], suffix)
            end
          end
          [base] + continuations
        end
      end

      def path_with_match(index, score, suffix)
        AlignmentPath.new(
          matched: 1 + (suffix&.matched || 0),
          score_sum: score + (suffix&.score_sum || 0.0),
          first_idx: index,
          last_idx: suffix ? suffix.last_idx : index,
          previous: suffix,
          safe_gap: suffix.nil? || (suffix.safe_gap && source_gap_safe?(index, suffix.first_idx))
        )
      end

      def suffix_best_paths(options)
        best_match = Array.new(source_tokens.length + 1) { [] }
        option_position = options.length - 1
        next_frontier = []
        (source_tokens.length - 1).downto(0) do |source_position|
          while option_position >= 0 && options[option_position].first_idx >= source_position
            append_path(best_match[source_position], options[option_position])
            option_position -= 1
          end

          if barrier_token?(source_position)
            best_match[source_position] = prune_frontier(best_match[source_position])
            next_frontier = []
          else
            best_match[source_position] = merge_path_frontiers(best_match[source_position], next_frontier)
            next_frontier = best_match[source_position]
          end
        end
        best_match
      end

      def merge_path_frontiers(left, right)
        return right if left.empty?
        return left if right.empty?

        merged = Array.new([left.length, right.length].max) { [] }
        [left, right].each do |frontier|
          frontier.each_with_index do |paths, count|
            merged[count] = prune_paths(merged[count] + paths.to_a)
          end
        end
        merged
      end

      def append_path(frontier, path)
        frontier[path.matched] ||= []
        frontier[path.matched] << path
      end

      def prune_frontier(frontier)
        frontier.map { |paths| prune_paths(paths.to_a) }
      end

      def prune_paths(paths)
        candidates = paths.uniq { |path| path_signature(path) }
        nondominated = candidates.reject do |candidate|
          candidates.any? do |other|
            other != candidate && dominates_path?(other, candidate)
          end
        end
        return nondominated if nondominated.length <= MAX_PATH_ALTERNATIVES_PER_MATCH_COUNT

        score_order = nondominated.sort_by { |path| [-path.score_sum, path.last_idx, path.first_idx] }
        compact_order = nondominated.sort_by { |path| [path.last_idx, -path.score_sum, path.first_idx] }
        (score_order.first(MAX_PATH_ALTERNATIVES_PER_MATCH_COUNT / 2) +
          compact_order.first(MAX_PATH_ALTERNATIVES_PER_MATCH_COUNT / 2)).uniq.first(
            MAX_PATH_ALTERNATIVES_PER_MATCH_COUNT
          )
      end

      def path_signature(path)
        [path.first_idx, path.last_idx, path.score_sum, path.safe_gap]
      end

      def dominates_path?(left, right)
        left.score_sum >= right.score_sum &&
          left.last_idx <= right.last_idx &&
          left.first_idx <= right.first_idx &&
          (!right.safe_gap || left.safe_gap)
      end

      def preferred_path(paths, target_count)
        candidates = paths.compact.flat_map { |paths_for_count| paths_for_count }
        return nil if candidates.empty?

        alignments = candidates.map { |path| subsequence_alignment(path) }
        feasible = alignments.select { |alignment| feasible?(alignment, target_count) }
        return alignments.max_by { |alignment| fallback_alignment_priority(alignment) } if feasible.empty?

        feasible.max_by { |alignment| alignment_priority(alignment) }
      end

      def subsequence_alignment(path)
        SubsequenceAlignment.new(
          matched: path.matched,
          window_size: path.last_idx - path.first_idx + 1,
          token_indices: path_indices(path),
          score: path.score_sum / path.matched
        )
      end

      def path_indices(path)
        indices = Array.new(path.matched)
        current = path
        path.matched.times do |position|
          indices[position] = current.first_idx
          current = current.previous
        end
        indices
      end

      def alignment_priority(alignment)
        [alignment.score, alignment.matched, -alignment.token_indices.first, -alignment.window_size]
      end

      def fallback_alignment_priority(alignment)
        [alignment.matched, alignment.score, -alignment.token_indices.first, -alignment.window_size]
      end

      def safe_source_gap?(token_indices)
        token_indices.each_cons(2).all? do |left_idx, right_idx|
          source_gap_safe?(left_idx, right_idx)
        end
      end

      def source_gap_safe?(left_idx, right_idx)
        barrier_prefix[right_idx] == barrier_prefix[left_idx + 1]
      end

      def barrier_token?(index)
        token = source_tokens[index]
        sentence_boundary_punctuation?(token.text) || negation_token?(token.text)
      end

      def barrier_prefix
        @barrier_prefix ||= source_tokens.each_with_object([0]) do |token, prefix|
          barrier = sentence_boundary_punctuation?(token.text) || negation_token?(token.text)
          prefix << (prefix.last + (barrier ? 1 : 0))
        end
      end

      def sentence_boundary_punctuation?(text)
        text.match?(SENTENCE_BOUNDARY_PUNCTUATION)
      end

      def negation_token?(text)
        normalized = TokenSimilarity.normalize(text)
        NEGATION_TOKENS.include?(normalized) || normalized.end_with?("n't", "n’t")
      end
    end
  end
end
