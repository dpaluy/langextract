# frozen_string_literal: true

require_relative "data"
require_relative "fuzzy_aligner"
require_relative "fuzzy_token_stream"
require_relative "token_similarity"
require_relative "tokenizer"

module LangExtract
  module Core
    # Resolves model extraction text to exact or fuzzy source intervals.
    class Resolver
      DEFAULT_FUZZY_THRESHOLD = 0.78
      DEFAULT_MIN_COVERAGE = 0.70
      DEFAULT_MIN_DENSITY = 0.34

      def initialize(text:, tokenizer: UnicodeTokenizer.new, fuzzy_threshold: DEFAULT_FUZZY_THRESHOLD,
                     allow_overlaps: false, suppress_alignment_errors: true,
                     min_coverage: DEFAULT_MIN_COVERAGE, min_density: DEFAULT_MIN_DENSITY)
        @text = text
        @tokenizer = tokenizer
        @fuzzy_threshold = fuzzy_threshold
        @allow_overlaps = allow_overlaps
        @suppress_alignment_errors = suppress_alignment_errors
        @min_coverage = min_coverage
        @min_density = min_density
        @tokens = tokenizer.tokenize(text)
        @fuzzy_token_stream = FuzzyTokenStream.new(tokens)
      end

      def resolve(items, document_id: nil, preferred_interval: nil)
        occupied = []

        items.map.with_index do |item, index|
          resolve_one(item, index, document_id, preferred_interval, occupied)
        end
      end

      private

      attr_reader :text, :tokens, :tokenizer, :fuzzy_threshold, :allow_overlaps, :suppress_alignment_errors,
                  :min_coverage, :min_density, :fuzzy_token_stream

      def resolve_one(item, index, document_id, preferred_interval, occupied)
        hash = HashCoercion.stringify_keys(item)
        extraction_text = hash.fetch("text").to_s

        interval, status = find_interval(extraction_text, preferred_interval, occupied)
        occupied << interval if interval && !overlap_status?(status)

        build_extraction(hash, extraction_text, interval, status, index, document_id)
      rescue AlignmentError
        raise unless suppress_alignment_errors

        build_extraction(hash || {}, extraction_text || "", nil, AlignmentStatus::ERROR, index, document_id)
      end

      def find_interval(extraction_text, preferred_interval, occupied)
        return [nil, AlignmentStatus::UNGROUNDED] if extraction_text.strip.empty?

        exact = find_exact(extraction_text, preferred_interval, occupied)
        return exact if exact

        fuzzy = find_fuzzy(extraction_text, preferred_interval, occupied)
        return fuzzy if fuzzy

        raise AlignmentError, "could not align extraction: #{extraction_text}" unless suppress_alignment_errors

        [nil, AlignmentStatus::UNGROUNDED]
      end

      def find_exact(extraction_text, preferred_interval, occupied)
        overlap_fallback = nil

        candidate_search_ranges(preferred_interval).each do |range|
          intervals = exact_intervals_in_range(extraction_text, range).uniq
          overlap_fallback ||= intervals.first
          non_overlap = intervals.find { |interval| allow_overlaps || !overlaps_any?(interval, occupied) }
          return [non_overlap, AlignmentStatus::EXACT] if non_overlap
        end

        overlap_fallback && [overlap_fallback, AlignmentStatus::OVERLAP]
      end

      def exact_intervals_in_range(extraction_text, range)
        intervals = case_sensitive_intervals(extraction_text, range)
        return intervals unless intervals.empty?

        case_insensitive_intervals(extraction_text, range)
      end

      def case_sensitive_intervals(extraction_text, range)
        intervals = []
        cursor = range.begin
        while cursor < range.end
          match_pos = text.index(extraction_text, cursor)
          break unless match_pos && match_pos < range.end

          end_pos = match_pos + extraction_text.length
          intervals << CharInterval.new(start_pos: match_pos, end_pos: end_pos) if end_pos <= range.end
          cursor = match_pos + 1
        end
        intervals
      end

      def case_insensitive_intervals(extraction_text, range)
        intervals = []
        pattern = Regexp.new(Regexp.escape(extraction_text), Regexp::IGNORECASE)
        cursor = range.begin
        while (match = pattern.match(text, cursor)) && match.begin(0) < range.end
          intervals << CharInterval.new(start_pos: match.begin(0), end_pos: match.end(0)) if match.end(0) <= range.end
          cursor = match.begin(0) + 1
        end
        intervals
      end

      def find_fuzzy(extraction_text, preferred_interval, occupied)
        target_tokens = tokenize_extraction(extraction_text)
        return nil if target_tokens.empty?

        overlap_fallback = nil
        candidate_search_ranges(preferred_interval).each do |range|
          candidates = fuzzy_candidates(target_tokens, range, occupied)
          overlap_fallback ||= candidates.first&.first
          non_overlap = candidates.find { |interval, _score| allow_overlaps || !overlaps_any?(interval, occupied) }
          return [non_overlap.first, AlignmentStatus::FUZZY] if non_overlap
        end

        overlap_fallback && [overlap_fallback, AlignmentStatus::OVERLAP]
      end

      def fuzzy_candidates(target_tokens, range, occupied)
        source_tokens = fuzzy_token_stream.tokens_in(range)
        return [] if source_tokens.empty?

        FuzzyAligner.new(
          source_tokens: source_tokens,
          fuzzy_threshold: fuzzy_threshold,
          min_coverage: min_coverage,
          min_density: min_density,
          allow_overlaps: allow_overlaps
        ).candidates(target_tokens, range, occupied)
      end

      def tokenize_extraction(extraction_text)
        tokenizer.tokenize(extraction_text.unicode_normalize(:nfc)).filter_map do |token|
          normalized = TokenSimilarity.normalize(token.text)
          normalized unless normalized.empty?
        end
      end

      def candidate_search_ranges(preferred_interval)
        ranges = []
        ranges << (preferred_interval.start_pos...preferred_interval.end_pos) if preferred_interval
        ranges << (0...text.length)
        ranges
      end

      def build_extraction(hash, extraction_text, interval, status, index, document_id)
        Extraction.new(
          extraction_class: hash["extraction_class"],
          text: extraction_text,
          description: hash["description"],
          attributes: hash["attributes"] || {},
          char_interval: interval,
          token_interval: interval ? token_interval_for(interval) : nil,
          alignment_status: status,
          extraction_index: index,
          group_id: hash["group_id"],
          document_id: document_id
        )
      end

      def token_interval_for(char_interval)
        matching = tokens.select { |token| token.char_interval.overlaps?(char_interval) }
        return nil if matching.empty?

        TokenInterval.new(start_pos: matching.first.index, end_pos: matching.last.index + 1)
      end

      def overlaps_any?(interval, occupied)
        occupied.any? { |other| interval.overlaps?(other) }
      end

      def overlap_status?(status)
        status == AlignmentStatus::OVERLAP
      end
    end
  end
end
