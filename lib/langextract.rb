# frozen_string_literal: true

require_relative "langextract/version"
require_relative "langextract/config"
require_relative "langextract/errors"
require_relative "langextract/core/errors"
require_relative "langextract/core/data"
require_relative "langextract/core/tokenizer"
require_relative "langextract/core/chunking"
require_relative "langextract/core/format_handler"
require_relative "langextract/core/prompt_validation"
require_relative "langextract/core/prompting"
require_relative "langextract/core/resolver"
require_relative "langextract/core/annotation"
require_relative "langextract/extractor"
require_relative "langextract/io"
require_relative "langextract/visualization"
require_relative "langextract/factory"

module LangExtract
  CharInterval = Core::CharInterval
  TokenInterval = Core::TokenInterval
  Extraction = Core::Extraction
  Document = Core::Document
  AnnotatedDocument = Core::AnnotatedDocument
  ExampleData = Core::ExampleData
  AlignmentStatus = Core::AlignmentStatus

  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield(config)
    end

    def reset_configuration!
      @config = nil
      Factory.reset_router!
    end

    def extract(**kwargs)
      text = kwargs.delete(:text)
      documents = kwargs.delete(:documents)
      Extractor.new(**kwargs).extract(text: text, documents: documents)
    end

    def visualize(input)
      Visualization.new.render(input)
    end
  end
end
