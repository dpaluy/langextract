# frozen_string_literal: true

require_relative "data"

module LangExtract
  module Core
    Token = Data.define(:text, :char_interval, :index) do
      def to_h
        {
          "text" => text,
          "char_interval" => char_interval.to_h,
          "index" => index
        }
      end
    end

    class RegexTokenizer
      DEFAULT_PATTERN = /\S+/

      def initialize(pattern: DEFAULT_PATTERN)
        @pattern = pattern
      end

      def tokenize(text)
        tokens = []
        text.to_enum(:scan, @pattern).each do
          match = Regexp.last_match
          tokens << Token.new(
            text: match[0],
            char_interval: CharInterval.new(start_pos: match.begin(0), end_pos: match.end(0)),
            index: tokens.length
          )
        end
        tokens.freeze
      end
    end

    class UnicodeTokenizer
      TOKEN_PATTERN = /
        \p{L}[\p{L}\p{M}\p{N}_'-]* |
        \p{N}+(?:[.,]\p{N}+)* |
        [^\s]
      /ux

      def tokenize(text)
        RegexTokenizer.new(pattern: TOKEN_PATTERN).tokenize(text)
      end
    end
  end
end
