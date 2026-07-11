# frozen_string_literal: true

require_relative "base"
require_relative "../core/types"
require "timeout"

module LangExtract
  module Providers
    class RubyLLMProvider < Base
      def infer(prompt:)
        require "ruby_llm"

        response = RubyLLM.chat(**chat_options).ask(prompt)
        InferenceResult.new(text: extract_text(response), raw: response)
      rescue LoadError => e
        raise Core::ProviderConfigError, "ruby_llm is required for live provider inference: #{e.message}"
      rescue StandardError => e
        error_class = provider_error_class(e)
        raise unless error_class

        raise error_class, "provider inference failed: #{e.message}"
      end

      private

      def provider_error_class(error)
        return Core::ProviderTimeoutError if timeout_error?(error)
        return Core::ProviderAuthError if ruby_llm_error?(error, :UnauthorizedError, :ForbiddenError,
                                                          :PaymentRequiredError)
        return Core::ProviderConfigError if ruby_llm_error?(error, :ConfigurationError)
        return Core::ProviderRateLimitError if ruby_llm_error?(error, :RateLimitError, :OverloadedError,
                                                               :ServiceUnavailableError)
        return Core::ProviderResponseError if defined?(RubyLLM::Error) && error.is_a?(RubyLLM::Error)

        nil
      end

      def timeout_error?(error)
        error.is_a?(Timeout::Error) || error.is_a?(Errno::ETIMEDOUT) ||
          (defined?(Faraday::TimeoutError) && error.is_a?(Faraday::TimeoutError)) ||
          error.class.name.to_s.match?(/timeout/i)
      end

      def ruby_llm_error?(error, *constant_names)
        return false unless defined?(RubyLLM)

        constant_names.any? do |constant_name|
          RubyLLM.const_defined?(constant_name, false) && error.is_a?(RubyLLM.const_get(constant_name))
        end
      end

      def chat_options
        options = config.options.dup
        options[:model] = config.model if config.model
        options[:provider] = config.provider if config.provider
        options
      end

      def extract_text(response)
        return response.content.to_s if response.respond_to?(:content)
        return response.text.to_s if response.respond_to?(:text)

        response.to_s
      end
    end
  end
end
