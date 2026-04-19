# frozen_string_literal: true

require "json"

require_relative "core/data"
require_relative "core/types"

module LangExtract
  module IO
    module_function

    def save_annotated_documents(path, documents)
      normalized = Array(documents)
      ::File.open(path, "w") do |file|
        normalized.each do |document|
          annotated = document.is_a?(Core::AnnotatedDocument) ? document : Core::AnnotatedDocument.from_h(document)
          file.puts(JSON.generate(annotated.to_h))
        end
      end
      path
    rescue SystemCallError, JSON::GeneratorError => e
      raise Core::IOFailure, "failed to save annotated documents: #{e.message}"
    end

    def load_annotated_documents_jsonl(path)
      ::File.readlines(path, chomp: true).filter_map do |line|
        next if line.strip.empty?

        Core::AnnotatedDocument.from_h(JSON.parse(line))
      end
    rescue SystemCallError, JSON::ParserError => e
      raise Core::IOFailure, "failed to load annotated documents: #{e.message}"
    end
  end
end
