# frozen_string_literal: true

require_relative "tokenizer"

module LangExtract
  module Core
    Chunk = Data.define(:text, :char_interval, :token_interval, :index, :document_id) do
      def to_h
        {
          "text" => text,
          "char_interval" => char_interval.to_h,
          "token_interval" => token_interval&.to_h,
          "index" => index,
          "document_id" => document_id
        }
      end
    end

    class SentenceAwareChunker
      DEFAULT_MAX_CHAR_BUFFER = 2_000

      def initialize(max_char_buffer: DEFAULT_MAX_CHAR_BUFFER, tokenizer: UnicodeTokenizer.new)
        raise ArgumentError, "max_char_buffer must be positive" unless max_char_buffer.positive?

        @max_char_buffer = max_char_buffer
        @tokenizer = tokenizer
      end

      def chunks(document)
        text = document.respond_to?(:text) ? document.text : document.to_s
        document_id = document.respond_to?(:id) ? document.id : nil
        sentences = sentence_intervals(text)
        token_lookup = token_lookup(text)
        build_chunks(text, sentences, token_lookup, document_id)
      end

      private

      attr_reader :max_char_buffer, :tokenizer

      def sentence_intervals(text)
        intervals = []
        start_pos = 0

        text.to_enum(:scan, /[.!?]+[)"'\]]*(?:\s+|$)|\n{2,}/).each do
          match = Regexp.last_match
          end_pos = match.end(0)
          intervals << CharInterval.new(start_pos: start_pos, end_pos: end_pos) if end_pos > start_pos
          start_pos = end_pos
        end

        intervals << CharInterval.new(start_pos: start_pos, end_pos: text.length) if start_pos < text.length
        intervals.reject { |interval| text[interval.start_pos...interval.end_pos].strip.empty? }
      end

      def build_chunks(text, sentences, token_lookup, document_id)
        return [] if text.empty?

        chunks = []
        current_start = nil
        current_end = nil

        sentences.each do |sentence|
          current_start ||= sentence.start_pos
          if current_end && sentence.end_pos - current_start > max_char_buffer
            chunks << build_chunk(text, current_start, current_end, token_lookup, chunks.length, document_id)
            current_start = sentence.start_pos
          end

          current_end = sentence.end_pos

          while current_end - current_start > max_char_buffer
            split_end = split_position(text, current_start)
            chunks << build_chunk(text, current_start, split_end, token_lookup, chunks.length, document_id)
            current_start = split_end
          end
        end

        if current_start && current_end
          chunks << build_chunk(text, current_start, current_end, token_lookup, chunks.length, document_id)
        end
        chunks.freeze
      end

      def split_position(text, start_pos)
        limit = [start_pos + max_char_buffer, text.length].min
        whitespace = text.rindex(/\s/, limit)
        return limit unless whitespace && whitespace > start_pos

        whitespace + 1
      end

      def build_chunk(text, start_pos, end_pos, token_lookup, index, document_id)
        interval = CharInterval.new(start_pos: start_pos, end_pos: end_pos)
        Chunk.new(
          text: text[start_pos...end_pos],
          char_interval: interval,
          token_interval: token_interval_for(interval, token_lookup),
          index: index,
          document_id: document_id
        )
      end

      def token_lookup(text)
        tokenizer.tokenize(text)
      end

      def token_interval_for(char_interval, tokens)
        matching = tokens.select { |token| token.char_interval.overlaps?(char_interval) }
        return nil if matching.empty?

        TokenInterval.new(start_pos: matching.first.index, end_pos: matching.last.index + 1)
      end
    end
  end
end
