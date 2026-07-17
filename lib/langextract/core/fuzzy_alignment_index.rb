# frozen_string_literal: true

require_relative "token_similarity"

module LangExtract
  module Core
    # Precomputed source-token lookup for fuzzy alignment. Similarity is
    # evaluated once per distinct normalized source text and target token.
    class FuzzyAlignmentIndex
      MatchingIndex = Data.define(:indices, :scores, :best_indices)

      def initialize(source_tokens)
        @source_tokens = source_tokens
      end

      def normalized_tokens
        @normalized_tokens ||= source_tokens.map { |token| TokenSimilarity.normalize(token.text) }
      end

      def matching_positions(target_token)
        @matching_positions_cache ||= {}
        normalized_target = TokenSimilarity.normalize(target_token)
        @matching_positions_cache[normalized_target] ||= build_matching_index(normalized_target)
      end

      def best_match(target_token, from_index)
        matching = matching_positions(target_token)
        position = matching.indices.bsearch_index { |idx| idx >= from_index }
        position && matching.best_indices[position]
      end

      private

      attr_reader :source_tokens

      def source_index
        @source_index ||= normalized_tokens.each_with_index.with_object({}) do |(normalized_text, idx), index|
          (index[normalized_text] ||= []) << idx
        end
      end

      def build_matching_index(normalized_target)
        pairs = matching_pairs(normalized_target).sort_by(&:first)
        indices = pairs.map(&:first)
        scores = pairs.map(&:last)
        MatchingIndex.new(
          indices: indices,
          scores: scores,
          best_indices: suffix_best_indices(indices, scores)
        )
      end

      def matching_pairs(normalized_target)
        source_index.each_with_object([]) do |(normalized_text, indices), matches|
          next unless TokenSimilarity.similar?(normalized_target, normalized_text)

          similarity = TokenSimilarity.char_similarity(normalized_target, normalized_text)
          indices.each { |idx| matches << [idx, similarity] }
        end
      end

      def suffix_best_indices(indices, scores)
        best_indices = Array.new(indices.length)
        best_position = nil
        (indices.length - 1).downto(0) do |position|
          best_position = better_score_position(position, best_position, indices, scores)
          best_indices[position] = indices[best_position]
        end
        best_indices
      end

      def better_score_position(position, best_position, indices, scores)
        return position if best_position.nil?
        return position if scores[position] > scores[best_position]
        return position if scores[position] == scores[best_position] && indices[position] < indices[best_position]

        best_position
      end
    end
  end
end
