# frozen_string_literal: true

require_relative "../core/errors"

module LangExtract
  module Providers
    class Router
      def initialize
        @providers = {}
      end

      def register(name, provider_class)
        providers[name.to_s] = provider_class
      end

      def fetch(name)
        providers.fetch(name.to_s) do
          raise Core::InvalidModelConfigError, "unknown provider adapter: #{name}"
        end
      end

      def create(config)
        fetch(config.adapter).new(config)
      end

      def names
        providers.keys.sort
      end

      private

      attr_reader :providers
    end
  end
end
