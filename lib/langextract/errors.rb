# frozen_string_literal: true

require_relative "core/errors"

module LangExtract
  Error = Core::Error
  InvalidModelConfigError = Core::InvalidModelConfigError
  ProviderError = Core::ProviderError
  ProviderConfigError = Core::ProviderConfigError
  ProviderAuthError = Core::ProviderAuthError
  ProviderRateLimitError = Core::ProviderRateLimitError
  ProviderTimeoutError = Core::ProviderTimeoutError
  ProviderResponseError = Core::ProviderResponseError
  FormatParsingError = Core::FormatParsingError
  PromptValidationError = Core::PromptValidationError
  AlignmentError = Core::AlignmentError
  IOFailure = Core::IOFailure
end
