# frozen_string_literal: true

module LangExtract
  module Core
    class Error < StandardError; end
    class InvalidModelConfigError < Error; end
    class ProviderError < Error; end
    class ProviderConfigError < ProviderError; end
    class ProviderAuthError < ProviderError; end
    class ProviderRateLimitError < ProviderError; end
    class ProviderTimeoutError < ProviderError; end
    class ProviderResponseError < ProviderError; end
    class FormatParsingError < Error; end
    class PromptValidationError < Error; end
    class AlignmentError < Error; end
    class IOFailure < Error; end
  end
end
