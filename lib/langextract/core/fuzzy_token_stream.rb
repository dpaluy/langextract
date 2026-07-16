# frozen_string_literal: true

require_relative "data"
require_relative "tokenizer"

module LangExtract
  module Core
    # Builds the temporary source-token stream used only by fuzzy alignment.
    # Canonical tokenizer output remains unchanged for exact and token offsets.
    class FuzzyTokenStream
      DASH_PUNCTUATION = /\p{Pd}/u
      # Commas are the grouping variant covered by the fuzzy contract.  Keep
      # periods intact so sentence-boundary barriers remain visible.
      NUMERIC_SEPARATOR = /,/u
      APOSTROPHE = /[\u0027\u2019]/u
      SEPARATOR_PUNCTUATION = /\A(?:\p{Pd}|,)\z/u

      def initialize(tokens)
        @tokens = tokens
      end

      def tokens_in(range)
        in_range = tokens.filter do |token|
          token.char_interval.start_pos >= range.begin && token.char_interval.end_pos <= range.end
        end
        pieces = in_range.flat_map { |token| split_boundary_punctuation(token) }
        merge_apostrophe_tokens(pieces).reject { |token| separator_punctuation?(token.text) }
      end

      private

      attr_reader :tokens

      def split_boundary_punctuation(token)
        pieces = []
        cursor = 0
        token.text.to_enum(:scan, /#{DASH_PUNCTUATION}|(?<=\p{N})#{NUMERIC_SEPARATOR}(?=\p{N})/u).each do
          match = Regexp.last_match
          append_token_piece(token, pieces, cursor, match.begin(0))
          append_token_piece(token, pieces, match.begin(0), match.end(0))
          cursor = match.end(0)
        end
        append_token_piece(token, pieces, cursor, token.text.length)
        pieces
      end

      def merge_apostrophe_tokens(pieces)
        merged = []
        index = 0
        while index < pieces.length
          current = pieces[index]
          if apostrophe?(current.text) && contiguous_text_pieces?(merged.last, pieces[index + 1], current)
            merged << merged_apostrophe_token(merged.pop, current, pieces[index + 1], merged.length)
            index += 2
          else
            merged << current
            index += 1
          end
        end
        reindex(merged)
      end

      def merged_apostrophe_token(previous, apostrophe, following, index)
        Token.new(
          text: previous.text + apostrophe.text + following.text,
          char_interval: CharInterval.new(
            start_pos: previous.char_interval.start_pos,
            end_pos: following.char_interval.end_pos
          ),
          index: index
        )
      end

      def reindex(tokens)
        tokens.each_with_index.map do |token, index|
          Token.new(text: token.text, char_interval: token.char_interval, index: index)
        end
      end

      def contiguous_text_pieces?(previous, following, apostrophe)
        previous && following &&
          previous.char_interval.end_pos == apostrophe.char_interval.start_pos &&
          apostrophe.char_interval.end_pos == following.char_interval.start_pos &&
          previous.text.match?(text_piece_pattern) && following.text.match?(text_piece_pattern)
      end

      def text_piece_pattern
        /\A[\p{L}\p{N}_-]+\z/u
      end

      def apostrophe?(text)
        text.match?(APOSTROPHE)
      end

      def separator_punctuation?(text)
        text.match?(SEPARATOR_PUNCTUATION)
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
