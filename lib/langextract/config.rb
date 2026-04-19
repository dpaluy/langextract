# frozen_string_literal: true

require "logger"

module LangExtract
  class Config
    attr_accessor :default_model, :logger

    def initialize
      @default_model = ENV.fetch("LANGEXTRACT_MODEL", nil)
      @logger = default_logger
    end

    private

    def default_logger
      defined?(Rails) ? Rails.logger : Logger.new($stderr)
    end
  end
end
