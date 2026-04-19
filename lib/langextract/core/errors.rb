# frozen_string_literal: true

module LangExtract
  module Core
    class Error < StandardError; end
    class InvalidModelConfigError < Error; end
    class ProviderConfigError < Error; end
    class FormatParsingError < Error; end
    class PromptValidationError < Error; end
    class AlignmentError < Error; end
    class IOFailure < Error; end
  end
end
