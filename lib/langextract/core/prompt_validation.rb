# frozen_string_literal: true

require_relative "data"
require_relative "types"

module LangExtract
  module Core
    class PromptValidation
      MODES = %i[off warning error].freeze

      def initialize(mode: :warning, warning_io: $stderr)
        @mode = mode.to_sym
        @warning_io = warning_io
        raise ArgumentError, "invalid prompt validation mode" unless MODES.include?(@mode)
      end

      def validate!(examples)
        return if mode == :off

        issues = examples.flat_map.with_index { |example, index| issues_for(example, index) }
        return if issues.empty?

        message = "Prompt examples failed validation: #{issues.join('; ')}"
        raise PromptValidationError, message if mode == :error

        warning_io.puts(message)
      end

      private

      attr_reader :mode, :warning_io

      def issues_for(example, index)
        normalized = example.is_a?(ExampleData) ? example : ExampleData.from_h(example)
        issues = []
        issues << "example #{index} text is empty" if normalized.text.strip.empty?
        issues << "example #{index} has no extractions" if normalized.extractions.empty?

        normalized.extractions.each_with_index do |extraction, extraction_index|
          extraction_text = extraction["text"] || extraction["extraction_text"]
          if extraction_text.to_s.strip.empty?
            issues << "example #{index} extraction #{extraction_index} text is empty"
          elsif !normalized.text.include?(extraction_text.to_s)
            issues << "example #{index} extraction #{extraction_index} text is not present in example text"
          end
        end

        issues
      end
    end
  end
end
