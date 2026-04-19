# frozen_string_literal: true

require "json"
require "yaml"

require_relative "data"

module LangExtract
  module Core
    class FormatHandler
      FENCE_PATTERN = /```(?:json|yaml|yml)?\s*(.*?)```/im

      def parse(output, format: :auto, strict: true, schema: nil)
        candidates = fenced_payloads(output)
        candidates << output.to_s if candidates.empty?

        parsed = parse_first(candidates, format)
        normalize_extractions(parsed).tap do |extractions|
          validate_schema!(extractions, schema) if schema
        end
      rescue FormatParsingError
        raise if strict

        []
      end

      private

      def fenced_payloads(output)
        output.to_s.scan(FENCE_PATTERN).flatten.map(&:strip).reject(&:empty?)
      end

      def parse_first(candidates, format)
        errors = []

        candidates.each do |candidate|
          parse_formats(format).each do |parser_format|
            parsed = parse_payload(candidate, parser_format)
            unless parsed.nil? || parsed == false || parsed.is_a?(Hash) || parsed.is_a?(Array)
              raise FormatParsingError, "parsed payload must be an object or array"
            end

            return parsed
          rescue JSON::ParserError, Psych::Exception, TypeError, FormatParsingError => e
            errors << "#{parser_format}: #{e.message}"
          end
        end

        raise FormatParsingError, "unable to parse provider output (#{errors.join('; ')})"
      end

      def parse_formats(format)
        case format.to_sym
        when :auto
          %i[json yaml]
        when :json, :yaml
          [format.to_sym]
        else
          raise FormatParsingError, "unsupported format: #{format}"
        end
      end

      def parse_payload(payload, format)
        case format
        when :json
          JSON.parse(payload)
        when :yaml
          YAML.safe_load(payload, permitted_classes: [Symbol], aliases: false)
        end
      end

      def normalize_extractions(parsed)
        payload = unwrap(parsed)
        extraction_items = payload.is_a?(Array) ? payload : [payload]

        extraction_items.compact.map do |item|
          normalize_extraction(item)
        end
      end

      def unwrap(parsed)
        return [] if parsed.nil? || parsed == false
        return parsed unless parsed.is_a?(Hash)

        hash = HashCoercion.stringify_keys(parsed)
        hash["extractions"] || hash["data"] || hash["items"] || hash
      end

      def normalize_extraction(item)
        raise FormatParsingError, "extraction must be an object" unless item.is_a?(Hash)

        hash = HashCoercion.stringify_keys(item)
        text = hash["text"] || hash["extraction_text"]
        raise FormatParsingError, "extraction text is required" if text.nil?

        {
          "extraction_class" => hash["extraction_class"] || hash["class"] || hash["type"],
          "text" => text.to_s,
          "description" => hash["description"],
          "attributes" => hash["attributes"] || {},
          "group_id" => hash["group_id"]
        }
      end

      def validate_schema!(extractions, schema)
        normalized_schema = HashCoercion.stringify_keys(schema)
        required = Array(normalized_schema["required"])
        properties = normalized_schema["properties"] || {}

        extractions.each_with_index do |extraction, index|
          required.each do |field|
            value = extraction[field.to_s]
            raise FormatParsingError, "schema validation failed: extraction #{index} missing #{field}" if blank?(value)
          end

          validate_property_types!(extraction, properties, index)
        end
      end

      def validate_property_types!(extraction, properties, index)
        properties.each do |field, rule|
          value = extraction[field]
          next if value.nil?

          expected_type = rule["type"]
          next if expected_type.nil? || matches_type?(value, expected_type)

          raise FormatParsingError, "schema validation failed: extraction #{index} #{field} must be #{expected_type}"
        end
      end

      def matches_type?(value, expected_type)
        case expected_type
        when "string"
          value.is_a?(String)
        when "object"
          value.is_a?(Hash)
        when "array"
          value.is_a?(Array)
        when "number"
          value.is_a?(Numeric)
        when "boolean"
          [true, false].include?(value)
        else
          true
        end
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
