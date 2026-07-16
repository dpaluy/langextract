# frozen_string_literal: true

require_relative "data"
require_relative "tokenizer"

module LangExtract
  module Core
    # Builds the temporary source-token stream used only by fuzzy alignment.
    # Canonical tokenizer output remains unchanged for exact and token offsets.
    class FuzzyTokenStream
      DASH_PUNCTUATION = /\p{Pd}/u

      def initialize(tokens)
        @tokens = tokens
      end

      def tokens_in(range)
        in_range = tokens.filter do |token|
          token.char_interval.start_pos >= range.begin && token.char_interval.end_pos <= range.end
        end
        in_range.flat_map { |token| split_boundary_punctuation(token) }
      end

      private

      attr_reader :tokens

      def split_boundary_punctuation(token)
        pieces = []
        cursor = 0
        token.text.to_enum(:scan, DASH_PUNCTUATION).each do
          match = Regexp.last_match
          append_token_piece(token, pieces, cursor, match.begin(0))
          append_token_piece(token, pieces, match.begin(0), match.end(0))
          cursor = match.end(0)
        end
        append_token_piece(token, pieces, cursor, token.text.length)
        pieces
      end

      def append_token_piece(token, pieces, start_pos, end_pos)
        return if start_pos >= end_pos

        pieces << Token.new(
          text: token.text[start_pos...end_pos],
          char_interval: CharInterval.new(
            start_pos: token.char_interval.start_pos + start_pos,
            end_pos: token.char_interval.start_pos + end_pos
          ),
          index: pieces.length
        )
      end
    end
  end
end
