# frozen_string_literal: true

require_relative "data"
require_relative "tokenizer"

module LangExtract
  module Core
    class Resolver
      DEFAULT_FUZZY_THRESHOLD = 0.78
      MAX_FUZZY_CANDIDATE_STARTS = 4_000
      Match = Data.define(:left_start, :right_start, :span_length)

      def initialize(text:, tokenizer: UnicodeTokenizer.new, fuzzy_threshold: DEFAULT_FUZZY_THRESHOLD,
                     allow_overlaps: false, suppress_alignment_errors: true)
        @text = text
        @tokenizer = tokenizer
        @fuzzy_threshold = fuzzy_threshold
        @allow_overlaps = allow_overlaps
        @suppress_alignment_errors = suppress_alignment_errors
        @tokens = tokenizer.tokenize(text)
      end

      def resolve(items, document_id: nil, preferred_interval: nil)
        occupied = []

        items.map.with_index do |item, index|
          resolve_one(item, index, document_id, preferred_interval, occupied)
        end
      end

      private

      attr_reader :text, :tokens, :fuzzy_threshold, :allow_overlaps, :suppress_alignment_errors

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
        intervals = candidate_search_ranges(preferred_interval).flat_map do |range|
          exact_intervals_in_range(extraction_text, range)
        end
        intervals = intervals.uniq
        return nil if intervals.empty?

        first_non_overlap = intervals.find { |interval| allow_overlaps || !overlaps_any?(interval, occupied) }
        return [first_non_overlap, AlignmentStatus::EXACT] if first_non_overlap

        [intervals.first, AlignmentStatus::OVERLAP]
      end

      def exact_intervals_in_range(extraction_text, range)
        intervals = []
        cursor = range.begin

        while cursor < range.end
          match_pos = text.index(extraction_text, cursor)
          break unless match_pos && match_pos < range.end

          end_pos = match_pos + extraction_text.length
          intervals << CharInterval.new(start_pos: match_pos, end_pos: end_pos) if end_pos <= range.end
          cursor = match_pos + 1
        end

        if intervals.empty?
          downcase_text = text[range].downcase
          downcase_target = extraction_text.downcase
          local_pos = downcase_text.index(downcase_target)
          if local_pos
            intervals << CharInterval.new(
              start_pos: range.begin + local_pos,
              end_pos: range.begin + local_pos + extraction_text.length
            )
          end
        end

        intervals
      end

      def find_fuzzy(extraction_text, preferred_interval, occupied)
        target = normalize_for_match(extraction_text)
        return nil if target.empty?

        candidates = candidate_search_ranges(preferred_interval).flat_map do |range|
          fuzzy_candidates_in_range(extraction_text, target, range)
        end
        candidates = ranked_unique_candidates(candidates)
        return nil if candidates.empty?

        non_overlap = candidates.find { |interval, _score| allow_overlaps || !overlaps_any?(interval, occupied) }
        return [non_overlap.first, AlignmentStatus::FUZZY] if non_overlap

        [candidates.first.first, AlignmentStatus::OVERLAP]
      end

      def fuzzy_candidates_in_range(extraction_text, normalized_target, range)
        target_length = extraction_text.length
        min_length = [1, (target_length * 0.65).floor].max
        max_length = [(target_length * 1.35).ceil, min_length].max
        candidates = []

        candidate_start_positions(range).each do |start_pos|
          (min_length..max_length).each do |length|
            end_pos = start_pos + length
            next if end_pos > range.end

            candidate = text[start_pos...end_pos]
            score = similarity(normalized_target, normalize_for_match(candidate))
            next if score < fuzzy_threshold

            candidates << [
              CharInterval.new(start_pos: start_pos, end_pos: end_pos),
              score
            ]
          end
        end

        candidates
      end

      def candidate_start_positions(range)
        starts = tokens.filter_map do |token|
          start_pos = token.char_interval.start_pos
          start_pos if start_pos >= range.begin && start_pos < range.end
        end.uniq

        return starts.first(MAX_FUZZY_CANDIDATE_STARTS) unless starts.empty?

        (range.begin...range.end).reject { |position| text[position].match?(/\s/) }.first(MAX_FUZZY_CANDIDATE_STARTS)
      end

      def ranked_unique_candidates(candidates)
        best_by_interval = candidates.each_with_object({}) do |(interval, score), result|
          key = [interval.start_pos, interval.end_pos]
          result[key] = [interval, score] if result[key].nil? || score > result[key].last
        end

        best_by_interval.values.sort_by { |interval, score| [-score, interval.start_pos, interval.end_pos] }
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

      def normalize_for_match(value)
        value.to_s.unicode_normalize(:nfc).downcase.gsub(/\s+/, " ").strip
      end

      def similarity(left, right)
        return 1.0 if left == right
        return 0.0 if left.empty? || right.empty?

        matches = sequence_match_count(left.each_char.to_a, right.each_char.to_a)
        (2.0 * matches) / (left.length + right.length)
      end

      def sequence_match_count(left_chars, right_chars, left_range = 0...left_chars.length,
                               right_range = 0...right_chars.length)
        match = longest_common_substring(left_chars, right_chars, left_range, right_range)
        return 0 unless match.span_length.positive?

        left_count = sequence_match_count(
          left_chars,
          right_chars,
          left_range.begin...match.left_start,
          right_range.begin...match.right_start
        )
        right_count = sequence_match_count(
          left_chars,
          right_chars,
          (match.left_start + match.span_length)...left_range.end,
          (match.right_start + match.span_length)...right_range.end
        )

        match.span_length + left_count + right_count
      end

      def longest_common_substring(left_chars, right_chars, left_range, right_range)
        best = Match.new(left_start: left_range.begin, right_start: right_range.begin, span_length: 0)
        previous_lengths = Array.new(right_range.size + 1, 0)

        left_range.each do |left_index|
          current_lengths = Array.new(right_range.size + 1, 0)
          right_range.each_with_index do |right_index, offset|
            next unless left_chars[left_index] == right_chars[right_index]

            length = previous_lengths[offset] + 1
            current_lengths[offset + 1] = length
            next unless length > best.span_length

            best = Match.new(
              left_start: left_index - length + 1,
              right_start: right_index - length + 1,
              span_length: length
            )
          end
          previous_lengths = current_lengths
        end

        best
      end
    end
  end
end
