# frozen_string_literal: true

require_relative "data"
require_relative "tokenizer"

module LangExtract
  module Core
    # Per-token similarity gate used by the token-level fuzzy aligner.
    # Prevents near-word substitutions (humane→human, chart→cart) by
    # requiring both a length-ratio floor and a character-similarity floor.
    module TokenSimilarity
      MIN_LENGTH_RATIO = 0.85
      MIN_CHAR_SIMILARITY = 0.78

      module_function

      def similar?(target_token, source_token)
        target = normalize(target_token)
        source = normalize(source_token)
        return true if target == source
        return false if target.empty? || source.empty?

        ratio = [target.length, source.length].min.to_f / [target.length, source.length].max
        return false if ratio < MIN_LENGTH_RATIO

        char_similarity(target, source) >= MIN_CHAR_SIMILARITY
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfc).downcase.gsub(/\s+/, " ").strip
      end

      def char_similarity(left, right)
        return 1.0 if left == right
        return 0.0 if left.empty? || right.empty?

        matches = SequenceMatcher.match_count(left.each_char.to_a, right.each_char.to_a)
        (2.0 * matches) / (left.length + right.length)
      end
    end

    # Longest-common-substring sequence matcher used for per-token character
    # similarity scoring (equivalent to Python's SequenceMatcher.ratio()).
    module SequenceMatcher
      Match = Data.define(:left_start, :right_start, :span_length)

      module_function

      def match_count(left_chars, right_chars)
        recursive_match_count(left_chars, right_chars, 0...left_chars.length, 0...right_chars.length)
      end

      def recursive_match_count(left_chars, right_chars, left_range, right_range)
        match = longest_common_substring(left_chars, right_chars, left_range, right_range)
        return 0 unless match.span_length.positive?

        left_count = recursive_match_count(
          left_chars, right_chars,
          left_range.begin...match.left_start,
          right_range.begin...match.right_start
        )
        right_count = recursive_match_count(
          left_chars, right_chars,
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

    # Token-level ordered-subsequence fuzzy aligner (issue #9).
    # Finds the best ordered-subsequence alignment of target tokens within
    # source tokens, applying per-token similarity, coverage, and density gates.
    class FuzzyAligner
      # Maximum number of candidate start positions to attempt alignment from.
      # Bounds the O(N²) worst case when many source tokens match the first
      # target token.
      MAX_FUZZY_CANDIDATE_STARTS = 4_000

      # Result of a single ordered-subsequence alignment attempt.
      SubsequenceAlignment = Data.define(:matched, :window_size, :token_indices, :score)

      def initialize(source_tokens:, fuzzy_threshold:, min_coverage:, min_density:, allow_overlaps:)
        @source_tokens = source_tokens
        @fuzzy_threshold = fuzzy_threshold
        @min_coverage = min_coverage
        @min_density = min_density
        @allow_overlaps = allow_overlaps
      end

      # Returns an array of [CharInterval, score] candidates, ranked by score
      # descending then by start position ascending.
      def candidates(target_tokens, range, occupied)
        alignments = all_subsequence_alignments(target_tokens)
        return [] if alignments.empty?

        found = alignments.filter_map do |alignment|
          next unless passes_gates?(alignment, target_tokens.length)

          interval = interval_for_alignment(alignment.token_indices, range)
          next unless interval
          next if alignment.score < fuzzy_threshold

          match = [interval, alignment.score]
          return [match] if alignment.score >= 1.0 && (allow_overlaps || !overlaps_any?(interval, occupied))

          match
        end

        ranked_unique_candidates(found)
      end

      private

      attr_reader :source_tokens, :fuzzy_threshold, :min_coverage, :min_density, :allow_overlaps

      def all_subsequence_alignments(target_tokens)
        first_target = target_tokens.first
        valid_starts = (0...source_tokens.length).each_with_object([]) do |idx, starts|
          source_norm = TokenSimilarity.normalize(source_tokens[idx].text)
          starts << idx if TokenSimilarity.similar?(first_target, source_norm)
        end
        return [] if valid_starts.empty?

        # Bound candidate-start enumeration to prevent O(N²) blowup when the
        # first target token matches many source tokens (issue #9 review).
        bounded_starts = valid_starts.first(MAX_FUZZY_CANDIDATE_STARTS)

        seen = {}
        bounded_starts.each_with_object([]) do |start, alignments|
          alignment = align_from_start(target_tokens, start)
          next unless alignment

          key = alignment.token_indices
          next if seen[key]

          seen[key] = true
          alignments << alignment
        end
      end

      def align_from_start(target_tokens, source_start)
        matched = 0
        source_idx = source_start
        token_indices = []
        similarities = []

        target_tokens.each do |target_token|
          match_idx = find_token_match(target_token, source_idx)
          return nil unless match_idx

          source_norm = TokenSimilarity.normalize(source_tokens[match_idx].text)
          matched += 1
          token_indices << match_idx
          similarities << TokenSimilarity.char_similarity(target_token, source_norm)
          source_idx = match_idx + 1
        end

        return nil if token_indices.empty?

        window_end = token_indices.last + 1
        score = similarities.sum.to_f / similarities.length
        SubsequenceAlignment.new(
          matched: matched,
          window_size: window_end - source_start,
          token_indices: token_indices,
          score: score
        )
      end

      def find_token_match(target_token, from_index)
        from_index.upto(source_tokens.length - 1) do |idx|
          source_norm = TokenSimilarity.normalize(source_tokens[idx].text)
          return idx if TokenSimilarity.similar?(target_token, source_norm)
        end
        nil
      end

      def passes_gates?(alignment, target_count)
        return false if target_count.zero?

        coverage = alignment.matched.to_f / target_count
        density = alignment.matched.to_f / alignment.window_size

        coverage >= min_coverage && density >= min_density
      end

      def interval_for_alignment(token_indices, range)
        return nil if token_indices.empty?

        first_token = source_tokens[token_indices.first]
        last_token = source_tokens[token_indices.last]

        start_pos = [first_token.char_interval.start_pos, range.begin].max
        end_pos = [last_token.char_interval.end_pos, range.end].min

        return nil if start_pos >= end_pos

        CharInterval.new(start_pos: start_pos, end_pos: end_pos)
      end

      def ranked_unique_candidates(candidates)
        best_by_interval = candidates.each_with_object({}) do |(interval, score), result|
          key = [interval.start_pos, interval.end_pos]
          result[key] = [interval, score] if result[key].nil? || score > result[key].last
        end

        best_by_interval.values.sort_by { |interval, score| [-score, interval.start_pos, interval.end_pos] }
      end

      def overlaps_any?(interval, occupied)
        occupied.any? { |other| interval.overlaps?(other) }
      end
    end

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
      end

      def resolve(items, document_id: nil, preferred_interval: nil)
        occupied = []

        items.map.with_index do |item, index|
          resolve_one(item, index, document_id, preferred_interval, occupied)
        end
      end

      private

      attr_reader :text, :tokens, :tokenizer, :fuzzy_threshold, :allow_overlaps, :suppress_alignment_errors,
                  :min_coverage, :min_density

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

      # --- Exact alignment (unchanged behavior) ---

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
        intervals = []
        cursor = range.begin
        range_end = range.end
        while cursor < range_end
          match_pos = text.index(extraction_text, cursor)
          break unless match_pos && match_pos < range_end

          end_pos = match_pos + extraction_text.length
          intervals << CharInterval.new(start_pos: match_pos, end_pos: end_pos) if end_pos <= range_end
          cursor = match_pos + 1
        end
        if intervals.empty?
          pattern = Regexp.new(Regexp.escape(extraction_text), Regexp::IGNORECASE)
          cursor = range.begin
          while (match = pattern.match(text, cursor)) && match.begin(0) < range_end
            intervals << CharInterval.new(start_pos: match.begin(0), end_pos: match.end(0)) if match.end(0) <= range_end
            cursor = match.begin(0) + 1
          end
        end

        intervals
      end

      # --- Token-level ordered-subsequence fuzzy alignment (issue #9) ---

      def find_fuzzy(extraction_text, preferred_interval, occupied)
        target_tokens = tokenize_extraction(extraction_text)
        return nil if target_tokens.empty?

        overlap_fallback = nil

        candidate_search_ranges(preferred_interval).each do |range|
          source_tokens = tokens_in_range(range)
          next if source_tokens.empty?

          aligner = FuzzyAligner.new(
            source_tokens: source_tokens,
            fuzzy_threshold: fuzzy_threshold,
            min_coverage: min_coverage,
            min_density: min_density,
            allow_overlaps: allow_overlaps
          )
          candidates = aligner.candidates(target_tokens, range, occupied)
          overlap_fallback ||= candidates.first&.first
          non_overlap = candidates.find { |interval, _score| allow_overlaps || !overlaps_any?(interval, occupied) }
          return [non_overlap.first, AlignmentStatus::FUZZY] if non_overlap
        end

        overlap_fallback && [overlap_fallback, AlignmentStatus::OVERLAP]
      end

      def tokenize_extraction(extraction_text)
        tokens = tokenizer.tokenize(extraction_text.unicode_normalize(:nfc))
        tokens.map { |token| TokenSimilarity.normalize(token.text) }.reject(&:empty?)
      end

      def tokens_in_range(range)
        tokens.select do |token|
          token.char_interval.start_pos >= range.begin && token.char_interval.end_pos <= range.end
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
