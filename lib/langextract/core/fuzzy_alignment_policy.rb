# frozen_string_literal: true

require_relative "token_similarity"

module LangExtract
  module Core
    # Validates semantic constraints that depend on the target-to-source token
    # mapping rather than only the selected source interval.
    class FuzzyAlignmentPolicy
      NEGATION_TOKENS = %w[
        aint arent cannot cant couldnt deny denied denies denying didnt doesnt
        dont hadnt hardly hasnt havent isnt mustnt neither neednt never no none
        not shouldnt shant wasnt werent without wont wouldnt
      ].freeze

      MappingState = Data.define(
        :last_target_index,
        :score_sum,
        :has_exact_match,
        :has_short_typo,
        :negation_mask
      )

      def self.negation_token?(text)
        NEGATION_TOKENS.include?(TokenSimilarity.normalize(text))
      end

      def initialize(source_tokens:, fuzzy_threshold:)
        @source_tokens = source_tokens
        @fuzzy_threshold = fuzzy_threshold
      end

      # Returns the best semantically valid average score, or nil when the
      # selected source tokens cannot be mapped safely to the target tokens.
      def score_for(target_tokens, source_indices)
        return nil if target_tokens.empty? || source_indices.empty?

        states = [initial_state]
        source_indices.each do |source_index|
          states = advance_states(states, target_tokens, source_tokens.fetch(source_index).text)
          return nil if states.empty?
        end

        best_valid_score(states, required_negation_mask(target_tokens), source_indices.length)
      end

      private

      attr_reader :source_tokens, :fuzzy_threshold

      def initial_state
        MappingState.new(
          last_target_index: -1,
          score_sum: 0.0,
          has_exact_match: false,
          has_short_typo: false,
          negation_mask: 0
        )
      end

      def best_valid_score(states, required_negations, matched_count)
        states.filter_map do |state|
          next unless valid_mapping?(state, required_negations, matched_count)

          score = state.score_sum / matched_count
          score if score >= fuzzy_threshold
        end.max
      end

      def valid_mapping?(state, required_negations, matched_count)
        return false unless state.negation_mask.allbits?(required_negations)
        return false if state.has_short_typo && (!state.has_exact_match || matched_count < 2)

        true
      end

      def advance_states(states, target_tokens, source_text)
        best_by_signature = {}
        states.each do |state|
          ((state.last_target_index + 1)...target_tokens.length).each do |target_index|
            target_text = target_tokens[target_index]
            next unless TokenSimilarity.similar?(target_text, source_text)

            candidate = extend_state(state, target_text, target_index, source_text)
            signature = state_signature(candidate)
            current = best_by_signature[signature]
            best_by_signature[signature] = candidate if current.nil? || candidate.score_sum > current.score_sum
          end
        end
        best_by_signature.values
      end

      def extend_state(state, target_text, target_index, source_text)
        target = TokenSimilarity.normalize(target_text)
        source = TokenSimilarity.normalize(source_text)
        exact = target == source
        negation_mask = state.negation_mask
        negation_mask |= (1 << target_index) if exact && negation_token?(target)

        MappingState.new(
          last_target_index: target_index,
          score_sum: state.score_sum + TokenSimilarity.char_similarity(target, source),
          has_exact_match: state.has_exact_match || exact,
          has_short_typo: state.has_short_typo || TokenSimilarity.short_typo?(target, source),
          negation_mask: negation_mask
        )
      end

      def state_signature(state)
        [state.last_target_index, state.has_exact_match, state.has_short_typo, state.negation_mask]
      end

      def required_negation_mask(target_tokens)
        target_tokens.each_with_index.reduce(0) do |mask, (token, index)|
          negation_token?(token) ? mask | (1 << index) : mask
        end
      end

      def negation_token?(text)
        self.class.negation_token?(text)
      end
    end
  end
end
