# frozen_string_literal: true

require "json"

require_relative "chunking"
require_relative "prompt_validation"

module LangExtract
  module Core
    class PromptBuilder
      def initialize(validation_mode: :warning, warning_io: $stderr)
        @validator = PromptValidation.new(mode: validation_mode, warning_io: warning_io)
      end

      def build(document:, chunk:, prompt_description:, examples: [], additional_context: nil,
                context_window_chars: 0, pass_index: nil, total_passes: 1)
        normalized_examples = examples.map { |example| normalize_example(example) }
        validator.validate!(normalized_examples)

        sections = []
        sections << "Task: #{prompt_description}"
        sections << "Additional context: #{additional_context}" if additional_context
        sections << pass_section(pass_index, total_passes) if total_passes.to_i > 1
        sections << context_section(document, chunk, context_window_chars) if context_window_chars.positive?
        sections << examples_section(normalized_examples) unless normalized_examples.empty?
        sections << "Text:\n#{chunk.text}"
        sections << output_contract
        sections.join("\n\n")
      end

      private

      attr_reader :validator

      def normalize_example(example)
        example.is_a?(ExampleData) ? example : ExampleData.from_h(example)
      end

      def context_section(document, chunk, context_window_chars)
        before_start = [chunk.char_interval.start_pos - context_window_chars, 0].max
        after_end = [chunk.char_interval.end_pos + context_window_chars, document.text.length].min
        before = document.text[before_start...chunk.char_interval.start_pos]
        after = document.text[chunk.char_interval.end_pos...after_end]

        "Context before:\n#{before}\n\nContext after:\n#{after}"
      end

      def examples_section(examples)
        rendered = examples.map.with_index do |example, index|
          [
            "Example #{index + 1} text:",
            example.text,
            "Example #{index + 1} extractions:",
            JSON.pretty_generate(example.extractions)
          ].join("\n")
        end

        rendered.join("\n\n")
      end

      def pass_section(pass_index, total_passes)
        "Extraction pass: #{pass_index + 1} of #{total_passes}. Return grounded extractions for this pass."
      end

      def output_contract
        <<~TEXT.strip
          Return JSON with an "extractions" array. Each extraction must include "text", and may include "extraction_class", "description", "attributes", and "group_id".
        TEXT
      end
    end
  end
end
