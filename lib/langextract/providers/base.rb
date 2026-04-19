# frozen_string_literal: true

module LangExtract
  module Providers
    InferenceResult = Data.define(:text, :raw)

    class Base
      def initialize(config)
        @config = config
      end

      def infer(prompt:)
        raise NotImplementedError, "#{self.class} must implement #infer"
      end

      private

      attr_reader :config
    end
  end
end
