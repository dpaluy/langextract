# frozen_string_literal: true

require "json"

require_relative "types"

module LangExtract
  module Core
    module HashCoercion
      module_function

      def stringify_keys(hash)
        (hash || {}).each_with_object({}) do |(key, value), result|
          result[key.to_s] = coerce_value(value)
        end
      end

      def coerce_value(value)
        case value
        when Hash
          stringify_keys(value)
        when Array
          value.map { |entry| coerce_value(entry) }.freeze
        else
          value
        end
      end

      def read(hash, *keys)
        keys.each do |key|
          return hash[key] if hash.key?(key)
          return hash[key.to_s] if hash.key?(key.to_s)
        end
        nil
      end
    end

    class CharInterval
      attr_reader :start_pos, :end_pos

      def initialize(start_pos:, end_pos:)
        raise ArgumentError, "start_pos must be non-negative" if start_pos.negative?
        raise ArgumentError, "end_pos must be >= start_pos" if end_pos < start_pos

        @start_pos = start_pos
        @end_pos = end_pos
        freeze
      end

      def length
        end_pos - start_pos
      end

      def overlaps?(other)
        start_pos < other.end_pos && other.start_pos < end_pos
      end

      def contains?(other)
        start_pos <= other.start_pos && end_pos >= other.end_pos
      end

      def shift(offset)
        self.class.new(start_pos: start_pos + offset, end_pos: end_pos + offset)
      end

      def to_h
        { "start_pos" => start_pos, "end_pos" => end_pos }
      end

      def self.from_h(hash)
        start_pos = HashCoercion.read(hash, :start_pos)
        end_pos = HashCoercion.read(hash, :end_pos)
        raise ArgumentError, "start_pos is required" if start_pos.nil?
        raise ArgumentError, "end_pos is required" if end_pos.nil?

        new(
          start_pos: start_pos.to_i,
          end_pos: end_pos.to_i
        )
      end

      def ==(other)
        other.is_a?(self.class) && start_pos == other.start_pos && end_pos == other.end_pos
      end
      alias eql? ==

      def hash
        [start_pos, end_pos].hash
      end

      def to_s
        "[#{start_pos}, #{end_pos})"
      end
    end

    class TokenInterval < CharInterval; end

    class Extraction
      attr_reader :extraction_class, :text, :description, :attributes, :char_interval,
                  :token_interval, :alignment_status, :extraction_index, :group_id,
                  :document_id

      def initialize(text:, extraction_class: nil, description: nil, attributes: {},
                     char_interval: nil, token_interval: nil,
                     alignment_status: AlignmentStatus::UNGROUNDED,
                     extraction_index: nil, group_id: nil, document_id: nil)
        raise ArgumentError, "text is required" if text.nil?
        raise ArgumentError, "invalid alignment status" unless AlignmentStatus.valid?(alignment_status)

        @extraction_class = extraction_class
        @text = text
        @description = description
        @attributes = HashCoercion.stringify_keys(attributes).freeze
        @char_interval = char_interval
        @token_interval = token_interval
        @alignment_status = alignment_status
        @extraction_index = extraction_index
        @group_id = group_id
        @document_id = document_id
        freeze
      end

      def grounded?
        char_interval && ![AlignmentStatus::UNGROUNDED, AlignmentStatus::ERROR].include?(alignment_status)
      end

      def to_h
        {
          "extraction_class" => extraction_class,
          "text" => text,
          "description" => description,
          "attributes" => attributes,
          "char_interval" => char_interval&.to_h,
          "token_interval" => token_interval&.to_h,
          "alignment_status" => alignment_status,
          "extraction_index" => extraction_index,
          "group_id" => group_id,
          "document_id" => document_id
        }
      end

      def self.from_h(hash)
        new(
          extraction_class: HashCoercion.read(hash, :extraction_class, :class, :type),
          text: HashCoercion.read(hash, :text, :extraction_text).to_s,
          description: HashCoercion.read(hash, :description),
          attributes: HashCoercion.read(hash, :attributes) || {},
          char_interval: interval_from_hash(HashCoercion.read(hash, :char_interval), CharInterval),
          token_interval: interval_from_hash(HashCoercion.read(hash, :token_interval), TokenInterval),
          alignment_status: HashCoercion.read(hash, :alignment_status) || AlignmentStatus::UNGROUNDED,
          extraction_index: HashCoercion.read(hash, :extraction_index),
          group_id: HashCoercion.read(hash, :group_id),
          document_id: HashCoercion.read(hash, :document_id)
        )
      end

      def self.interval_from_hash(value, interval_class)
        return value if value.is_a?(interval_class)
        return nil if value.nil?

        interval_class.from_h(value)
      end
    end

    class Document
      attr_reader :text, :id, :metadata

      def initialize(text:, id: nil, metadata: {})
        raise ArgumentError, "text is required" if text.nil?

        @text = text
        @id = id
        @metadata = HashCoercion.stringify_keys(metadata).freeze
        freeze
      end

      def to_h
        { "id" => id, "text" => text, "metadata" => metadata }
      end

      def self.from_h(hash)
        new(
          id: HashCoercion.read(hash, :id),
          text: HashCoercion.read(hash, :text).to_s,
          metadata: HashCoercion.read(hash, :metadata) || {}
        )
      end
    end

    class AnnotatedDocument
      attr_reader :document, :extractions

      def initialize(document:, extractions: [])
        @document = document
        @extractions = extractions.map { |item| item.is_a?(Extraction) ? item : Extraction.from_h(item) }.freeze
        freeze
      end

      def id
        document.id
      end

      def text
        document.text
      end

      def metadata
        document.metadata
      end

      def to_h
        {
          "document" => document.to_h,
          "extractions" => extractions.map(&:to_h)
        }
      end

      def self.from_h(hash)
        document_hash = HashCoercion.read(hash, :document)
        document = Document.from_h(document_hash || hash)
        extractions = Array(HashCoercion.read(hash, :extractions)).map { |item| Extraction.from_h(item) }

        new(document: document, extractions: extractions)
      end
    end

    class ExampleData
      attr_reader :text, :extractions

      def initialize(text:, extractions:)
        raise ArgumentError, "text is required" if text.nil?

        @text = text
        @extractions = extractions.map { |item| normalize_extraction(item) }.freeze
        freeze
      end

      def to_h
        {
          "text" => text,
          "extractions" => extractions
        }
      end

      def self.from_h(hash)
        new(
          text: HashCoercion.read(hash, :text).to_s,
          extractions: Array(HashCoercion.read(hash, :extractions))
        )
      end

      private

      def normalize_extraction(item)
        return example_hash_from_extraction(item) if item.is_a?(Extraction)

        HashCoercion.stringify_keys(item)
      end

      def example_hash_from_extraction(extraction)
        {
          "extraction_class" => extraction.extraction_class,
          "text" => extraction.text,
          "description" => extraction.description,
          "attributes" => extraction.attributes,
          "group_id" => extraction.group_id
        }
      end
    end
  end
end
