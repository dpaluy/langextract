# frozen_string_literal: true

require_relative "core/annotation"
require_relative "core/chunking"
require_relative "core/format_handler"
require_relative "core/prompting"

module LangExtract
  class Extractor
    DEFAULT_MAX_CHAR_BUFFER = Core::SentenceAwareChunker::DEFAULT_MAX_CHAR_BUFFER

    def initialize(model:, prompt_description:, examples: [], additional_context: nil,
                   max_char_buffer: DEFAULT_MAX_CHAR_BUFFER, context_window_chars: 0,
                   extraction_passes: 1, format: :auto, strict: true,
                   prompt_validation: :warning, suppress_parse_errors: false,
                   suppress_alignment_errors: true, allow_overlaps: false,
                   fuzzy_threshold: Core::Resolver::DEFAULT_FUZZY_THRESHOLD,
                   tokenizer: Core::UnicodeTokenizer.new)
      @model = model
      @prompt_description = prompt_description
      @examples = examples
      @additional_context = additional_context
      @max_char_buffer = max_char_buffer
      @context_window_chars = context_window_chars
      @extraction_passes = extraction_passes
      @format = format
      @strict = strict
      @prompt_validation = prompt_validation
      @suppress_parse_errors = suppress_parse_errors
      @suppress_alignment_errors = suppress_alignment_errors
      @allow_overlaps = allow_overlaps
      @fuzzy_threshold = fuzzy_threshold
      @tokenizer = tokenizer
      validate_model!
    end

    def extract(text: nil, documents: nil)
      coerced_documents = coerce_documents(text, documents)
      annotated = coerced_documents.map { |document| extract_document(document) }

      documents.nil? && !text.nil? ? annotated.first : annotated
    end

    private

    attr_reader :model, :prompt_description, :examples, :additional_context, :max_char_buffer,
                :context_window_chars, :extraction_passes, :format, :strict, :prompt_validation,
                :suppress_parse_errors, :suppress_alignment_errors, :allow_overlaps, :fuzzy_threshold,
                :tokenizer

    def extract_document(document)
      chunker = Core::SentenceAwareChunker.new(max_char_buffer: max_char_buffer, tokenizer: tokenizer)
      prompt_builder = Core::PromptBuilder.new(validation_mode: prompt_validation)
      format_handler = Core::FormatHandler.new
      extractions = []

      chunker.chunks(document).each do |chunk|
        extraction_passes.times do |pass_index|
          raw_output = infer(prompt_builder, document, chunk, pass_index)
          parsed = parse(format_handler, raw_output)
          resolver = Core::Resolver.new(
            text: document.text,
            tokenizer: tokenizer,
            fuzzy_threshold: fuzzy_threshold,
            allow_overlaps: allow_overlaps,
            suppress_alignment_errors: suppress_alignment_errors
          )
          extractions.concat(
            resolver.resolve(parsed, document_id: document.id, preferred_interval: chunk.char_interval)
          )
        end
      end

      Core::AnnotatedDocument.new(document: document, extractions: merge_extractions(extractions))
    end

    def infer(prompt_builder, document, chunk, pass_index)
      prompt = prompt_builder.build(
        document: document,
        chunk: chunk,
        prompt_description: prompt_description,
        examples: examples,
        additional_context: additional_context,
        context_window_chars: context_window_chars,
        pass_index: pass_index,
        total_passes: extraction_passes
      )
      call_model(prompt)
    end

    def call_model(prompt)
      result = model.infer(prompt: prompt)

      result.respond_to?(:text) ? result.text.to_s : result.to_s
    end

    def parse(format_handler, raw_output)
      format_handler.parse(raw_output, format: format, strict: strict)
    rescue Core::FormatParsingError
      raise unless suppress_parse_errors

      []
    end

    def merge_extractions(extractions)
      occupied = []
      seen = {}

      extractions.filter_map do |extraction|
        key = merge_key(extraction)
        next if seen[key]

        seen[key] = true
        if extraction.grounded?
          next if !allow_overlaps && occupied.any? { |interval| interval.overlaps?(extraction.char_interval) }

          occupied << extraction.char_interval
        end
        extraction
      end.freeze
    end

    def merge_key(extraction)
      interval = extraction.char_interval
      [
        extraction.document_id,
        interval&.start_pos,
        interval&.end_pos,
        extraction.text,
        extraction.description,
        extraction.extraction_class
      ]
    end

    def coerce_documents(text, documents)
      if documents
        Array(documents).map.with_index { |document, index| coerce_document(document, index) }
      elsif text
        [Core::Document.new(text: text, id: "document_0")]
      else
        raise ArgumentError, "text or documents is required"
      end
    end

    def coerce_document(document, index)
      return document if document.is_a?(Core::Document)
      return Core::Document.from_h(document) if document.is_a?(Hash)

      Core::Document.new(text: document.to_s, id: "document_#{index}")
    end

    def validate_model!
      return if model.respond_to?(:infer)

      raise Core::InvalidModelConfigError, "model must respond to #infer(prompt:)"
    end
  end
end
