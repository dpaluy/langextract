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
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Logger.new($stderr, progname: "langextract").tap { |logger| logger.level = Logger::WARN }
    end
  end
end
