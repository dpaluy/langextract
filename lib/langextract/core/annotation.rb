# frozen_string_literal: true

require_relative "resolver"

module LangExtract
  module Core
    class Annotator
      def initialize(tokenizer: UnicodeTokenizer.new, fuzzy_threshold: Resolver::DEFAULT_FUZZY_THRESHOLD,
                     suppress_alignment_errors: true)
        @tokenizer = tokenizer
        @fuzzy_threshold = fuzzy_threshold
        @suppress_alignment_errors = suppress_alignment_errors
      end

      def annotate(document:, extraction_hashes:, preferred_interval: nil)
        resolver = Resolver.new(
          text: document.text,
          tokenizer: tokenizer,
          fuzzy_threshold: fuzzy_threshold,
          suppress_alignment_errors: suppress_alignment_errors
        )
        extractions = resolver.resolve(
          extraction_hashes,
          document_id: document.id,
          preferred_interval: preferred_interval
        )

        AnnotatedDocument.new(document: document, extractions: extractions)
      end

      private

      attr_reader :tokenizer, :fuzzy_threshold, :suppress_alignment_errors
    end
  end
end
