# frozen_string_literal: true

require_relative "core/errors"

module LangExtract
  Error = Core::Error
  InvalidModelConfigError = Core::InvalidModelConfigError
  ProviderConfigError = Core::ProviderConfigError
  FormatParsingError = Core::FormatParsingError
  PromptValidationError = Core::PromptValidationError
  AlignmentError = Core::AlignmentError
  IOFailure = Core::IOFailure
end
