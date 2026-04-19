# frozen_string_literal: true

require_relative "base"
require_relative "../core/types"

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
        raise Core::ProviderConfigError, "provider inference failed: #{e.message}"
      end

      private

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
