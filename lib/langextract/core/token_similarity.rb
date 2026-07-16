# frozen_string_literal: true

module LangExtract
  module Core
    # Per-token similarity gate used by the token-level fuzzy aligner.
    # Prevents near-word substitutions (humane→human, chart→cart) by
    # requiring both a length-ratio floor and a character-similarity floor.
    module TokenSimilarity
      MIN_LENGTH_RATIO = 0.85
      MIN_CHAR_SIMILARITY = 0.78

      module_function

      def similar?(target_token, source_token)
        target = normalize(target_token)
        source = normalize(source_token)
        return true if target == source
        return false if target.empty? || source.empty?

        ratio = [target.length, source.length].min.to_f / [target.length, source.length].max
        return false if ratio < MIN_LENGTH_RATIO

        char_similarity(target, source) >= MIN_CHAR_SIMILARITY
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfc).downcase.gsub(/\s+/, " ").strip
      end

      def char_similarity(left, right)
        return 1.0 if left == right
        return 0.0 if left.empty? || right.empty?

        matches = SequenceMatcher.match_count(left.each_char.to_a, right.each_char.to_a)
        (2.0 * matches) / (left.length + right.length)
      end
    end

    # Longest-common-substring sequence matcher used for per-token character
    # similarity scoring (equivalent to Python's SequenceMatcher.ratio()).
    module SequenceMatcher
      Match = Data.define(:left_start, :right_start, :span_length)

      module_function

      def match_count(left_chars, right_chars)
        recursive_match_count(left_chars, right_chars, 0...left_chars.length, 0...right_chars.length)
      end

      def recursive_match_count(left_chars, right_chars, left_range, right_range)
        match = longest_common_substring(left_chars, right_chars, left_range, right_range)
        return 0 unless match.span_length.positive?

        left_count = recursive_match_count(
          left_chars, right_chars,
          left_range.begin...match.left_start,
          right_range.begin...match.right_start
        )
        right_count = recursive_match_count(
          left_chars, right_chars,
          (match.left_start + match.span_length)...left_range.end,
          (match.right_start + match.span_length)...right_range.end
        )

        match.span_length + left_count + right_count
      end

      def longest_common_substring(left_chars, right_chars, left_range, right_range)
        best = Match.new(left_start: left_range.begin, right_start: right_range.begin, span_length: 0)
        previous_lengths = Array.new(right_range.size + 1, 0)

        left_range.each do |left_index|
          current_lengths = Array.new(right_range.size + 1, 0)
          right_range.each_with_index do |right_index, offset|
            next unless left_chars[left_index] == right_chars[right_index]

            length = previous_lengths[offset] + 1
            current_lengths[offset + 1] = length
            next unless length > best.span_length

            best = Match.new(
              left_start: left_index - length + 1,
              right_start: right_index - length + 1,
              span_length: length
            )
          end
          previous_lengths = current_lengths
        end

        best
      end
    end
  end
end
