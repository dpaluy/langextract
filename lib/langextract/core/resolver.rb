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
    # rubocop:disable Metrics/ClassLength
    class FuzzyAligner
      # Historical candidate-start limit retained for compatibility with
      # callers that reference the constant. Indexed suffix alignment no
      # longer truncates starts, because each lookup is bounded.
      MAX_FUZZY_CANDIDATE_STARTS = 4_000

      # Keep a bounded Pareto frontier for each matched-token count. A later
      # exact token can have a higher score but a sparse window, so one winner
      # per count is insufficient; this bound prevents frontier growth with
      # document length.
      MAX_PATH_ALTERNATIVES_PER_MATCH_COUNT = 2

      # A fuzzy span may cross formatting punctuation (for example, a source
      # `New-York` can ground an extraction of `New York`), but a sentence
      # terminator is a hard boundary.  Keeping this policy at the token-gap
      # level preserves the ordered-subsequence behavior for ordinary
      # same-sentence modifiers while avoiding false cross-sentence spans.
      SENTENCE_BOUNDARY_PUNCTUATION = /[.!?\u2026\u3002\uff01\uff1f]/u

      # Conservative lexical negation barriers.  A skipped source token such
      # as `denies` or `not` changes the meaning of the surrounding matched
      # words, so it must not be hidden inside a fuzzy grounded interval.
      NEGATION_TOKENS = %w[
        cannot can't can’t deny denies denied denying
        no not none neither never without
      ].freeze

      # Result of a single ordered-subsequence alignment attempt.
      SubsequenceAlignment = Data.define(:matched, :window_size, :token_indices, :score)

      # Cached match positions for one normalized target token. `indices` and
      # `scores` are parallel, source-order arrays. `best_indices` stores the
      # highest-similarity candidate from each suffix and lets
      # `find_token_match` answer one lookup with a single binary search.
      MatchingIndex = Data.define(:indices, :scores, :best_indices)

      # Internal linked dynamic-programming path. Token indices are rebuilt
      # only for final candidates, avoiding an array copy for every DP option.
      AlignmentPath = Data.define(:matched, :score_sum, :first_idx, :last_idx, :previous, :safe_gap)

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
        # Consider every source position matching any target token. A target
        # may omit leading or interior words, so restricting starts to the
        # first target token can miss a valid partial-coverage path (for
        # example, a late `quickly` match while the earlier three words are
        # present). The suffix table makes each start O(1), so no truncation is
        # needed here.
        start_flags = Array.new(source_tokens.length, false)
        target_tokens.each do |target_token|
          matching_positions(target_token).indices.each { |idx| start_flags[idx] = true }
        end
        valid_starts = start_flags.each_index.select { |idx| start_flags[idx] }
        return [] if valid_starts.empty?

        seen = {}
        valid_starts.each_with_object([]) do |start, alignments|
          alignment = align_from_start(target_tokens, start)
          next unless alignment

          key = alignment.token_indices
          next if seen[key]

          seen[key] = true
          alignments << alignment
        end
      end

      def align_from_start(target_tokens, source_start)
        paths = alignment_table(target_tokens)[source_start]
        alignment = preferred_path(paths, target_tokens.length)
        return nil unless alignment

        alignment
      end

      # Find the earliest source token index >= from_index whose normalized
      # text passes the similarity gate for target_token. Uses a precomputed
      # index with binary-search lookup instead of a linear forward scan,
      # reducing per-start cost from O(N) to O(D · log N) where D is the
      # number of distinct source texts matching this target token.
      def find_token_match(target_token, from_index)
        matching = matching_positions(target_token)
        position = matching.indices.bsearch_index { |idx| idx >= from_index }
        position && matching.best_indices[position]
      end

      # Normalized source token texts, cached per instance to avoid
      # recomputing normalize on every alignment scan.
      def norm_source
        @norm_source ||= source_tokens.map { |token| TokenSimilarity.normalize(token.text) }
      end

      # Hash mapping each distinct normalized source text to its sorted list
      # of token indices, built once per instance and reused for every
      # find_token_match binary-search lookup.
      def source_index
        @source_index ||= norm_source.each_with_index.with_object({}) do |(norm_text, idx), index|
          (index[norm_text] ||= []) << idx
        end
      end

      # Build one sorted source-position index for a normalized target token.
      # Similarity is evaluated once per distinct source text, then every
      # alignment lookup is a binary search plus an O(1) suffix-best read.
      def matching_positions(target_token)
        @matching_positions_cache ||= {}
        normalized_target = TokenSimilarity.normalize(target_token)
        @matching_positions_cache[normalized_target] ||= build_matching_index(normalized_target)
      end

      def build_matching_index(normalized_target)
        pairs = matching_pairs(normalized_target).sort_by(&:first)
        indices = pairs.map(&:first)
        scores = pairs.map(&:last)
        best_indices = suffix_best_indices(indices, scores)
        MatchingIndex.new(indices: indices, scores: scores, best_indices: best_indices)
      end

      def matching_pairs(normalized_target)
        source_index.each_with_object([]) do |(norm_text, indices), matches|
          next unless TokenSimilarity.similar?(normalized_target, norm_text)

          similarity = TokenSimilarity.char_similarity(normalized_target, norm_text)
          indices.each { |idx| matches << [idx, similarity] }
        end
      end

      def suffix_best_indices(indices, scores)
        best_indices = Array.new(indices.length)
        best_position = nil
        (indices.length - 1).downto(0) do |position|
          best_position = better_score_position(position, best_position, indices, scores)
          best_indices[position] = indices[best_position]
        end
        best_indices
      end

      def better_score_position(position, best_position, indices, scores)
        return position if best_position.nil?
        return position if scores[position] > scores[best_position]
        return position if scores[position] == scores[best_position] && indices[position] < indices[best_position]

        best_position
      end

      # Compute a coverage/score frontier for every source start in one suffix
      # pass. Greedy per-token selection can jump to a later exact token and
      # lose a valid continuation; retaining bounded score/compactness
      # alternatives per match count keeps those tradeoffs available without
      # repeating work per candidate start.
      def alignment_table(target_tokens)
        @alignment_table_cache ||= {}
        key = target_tokens.map(&:to_s).freeze
        @alignment_table_cache[key] ||= build_alignment_table(target_tokens)
      end

      def build_alignment_table(target_tokens)
        next_row = Array.new(source_tokens.length + 1) { [] }
        target_tokens.reverse_each do |target_token|
          next_row = alignment_row(target_token, next_row)
        end
        next_row
      end

      def alignment_row(target_token, next_row)
        matching = matching_positions(target_token)
        options = alignment_options(matching, next_row)
        best_match = suffix_best_paths(options)
        row = Array.new(source_tokens.length + 1)
        source_tokens.length.downto(0) do |source_position|
          row[source_position] = merge_path_frontiers(best_match[source_position], next_row[source_position])
        end
        row
      end

      def alignment_options(matching, next_row)
        matching.indices.each_with_index.flat_map do |idx, position|
          suffixes = next_row[idx + 1]
          base = path_with_match(idx, matching.scores[position], nil)
          continuations = suffixes.to_a.flat_map do |suffixes_for_count|
            next [] unless suffixes_for_count

            suffixes_for_count.filter_map do |suffix|
              next unless suffix.safe_gap && source_gap_safe?(idx, suffix.first_idx)

              path_with_match(idx, matching.scores[position], suffix)
            end
          end
          [base] + continuations
        end
      end

      def path_with_match(index, score, suffix)
        AlignmentPath.new(
          matched: 1 + (suffix&.matched || 0),
          score_sum: score + (suffix&.score_sum || 0.0),
          first_idx: index,
          last_idx: suffix ? suffix.last_idx : index,
          previous: suffix,
          safe_gap: suffix.nil? || (suffix.safe_gap && source_gap_safe?(index, suffix.first_idx))
        )
      end

      def suffix_best_paths(options)
        best_match = Array.new(source_tokens.length + 1) { [] }
        option_position = options.length - 1
        next_frontier = []
        (source_tokens.length - 1).downto(0) do |source_position|
          while option_position >= 0 && options[option_position].first_idx >= source_position
            append_path(best_match[source_position], options[option_position])
            option_position -= 1
          end

          if barrier_token?(source_position)
            # A barrier starts a new segment for paths whose current target
            # token is matched before it. Keep candidates at the barrier for
            # starts within this segment, but do not propagate later matches
            # across it.
            best_match[source_position] = prune_frontier(best_match[source_position])
            next_frontier = []
          else
            best_match[source_position] = merge_path_frontiers(best_match[source_position], next_frontier)
            next_frontier = best_match[source_position]
          end
        end
        best_match
      end

      def merge_path_frontiers(left, right)
        return right if left.empty?
        return left if right.empty?

        merged = Array.new([left.length, right.length].max) { [] }
        [left, right].each do |frontier|
          frontier.each_with_index do |paths, count|
            merged[count] = prune_paths(merged[count] + paths.to_a)
          end
        end
        merged
      end

      def append_path(frontier, path)
        frontier[path.matched] ||= []
        frontier[path.matched] << path
      end

      def prune_frontier(frontier)
        frontier.map { |paths| prune_paths(paths.to_a) }
      end

      def prune_paths(paths)
        candidates = paths.uniq { |path| path_signature(path) }
        nondominated = candidates.reject do |candidate|
          candidates.any? do |other|
            other != candidate && dominates_path?(other, candidate)
          end
        end
        return nondominated if nondominated.length <= MAX_PATH_ALTERNATIVES_PER_MATCH_COUNT

        score_order = nondominated.sort_by { |path| [-path.score_sum, path.last_idx, path.first_idx] }
        compact_order = nondominated.sort_by { |path| [path.last_idx, -path.score_sum, path.first_idx] }
        (score_order.first(MAX_PATH_ALTERNATIVES_PER_MATCH_COUNT / 2) +
          compact_order.first(MAX_PATH_ALTERNATIVES_PER_MATCH_COUNT / 2)).uniq.first(
            MAX_PATH_ALTERNATIVES_PER_MATCH_COUNT
          )
      end

      def path_signature(path)
        [path.first_idx, path.last_idx, path.score_sum, path.safe_gap]
      end

      def dominates_path?(left, right)
        left.score_sum >= right.score_sum &&
          left.last_idx <= right.last_idx &&
          left.first_idx <= right.first_idx &&
          (!right.safe_gap || left.safe_gap)
      end

      def preferred_path(paths, target_count)
        candidates = paths.compact.flat_map { |paths_for_count| paths_for_count }
        return nil if candidates.empty?

        alignments = candidates.map { |path| subsequence_alignment(path) }
        feasible = alignments.select do |alignment|
          alignment.score >= fuzzy_threshold && passes_gates?(alignment, target_count)
        end
        return alignments.max_by { |alignment| fallback_alignment_priority(alignment) } if feasible.empty?

        feasible.max_by { |alignment| alignment_priority(alignment) }
      end

      def subsequence_alignment(path)
        indices = path_indices(path)
        SubsequenceAlignment.new(
          matched: path.matched,
          window_size: path.last_idx - path.first_idx + 1,
          token_indices: indices,
          score: path.score_sum / path.matched
        )
      end

      def path_indices(path)
        indices = Array.new(path.matched)
        current = path
        path.matched.times do |position|
          indices[position] = current.first_idx
          current = current.previous
        end
        indices
      end

      def alignment_priority(alignment)
        [alignment.score, alignment.matched, -alignment.token_indices.first, -alignment.window_size]
      end

      def fallback_alignment_priority(alignment)
        [alignment.matched, alignment.score, -alignment.token_indices.first, -alignment.window_size]
      end

      def passes_gates?(alignment, target_count)
        return false if target_count.zero?

        coverage = alignment.matched.to_f / target_count
        density = alignment.matched.to_f / alignment.window_size

        coverage >= min_coverage && density >= min_density && safe_source_gap?(alignment.token_indices)
      end

      def safe_source_gap?(token_indices)
        token_indices.each_cons(2).all? do |left_idx, right_idx|
          source_gap_safe?(left_idx, right_idx)
        end
      end

      def source_gap_safe?(left_idx, right_idx)
        barrier_prefix[right_idx] == barrier_prefix[left_idx + 1]
      end

      def barrier_token?(index)
        token = source_tokens[index]
        sentence_boundary_punctuation?(token.text) || negation_token?(token.text)
      end

      def barrier_prefix
        @barrier_prefix ||= source_tokens.each_with_object([0]) do |token, prefix|
          barrier = sentence_boundary_punctuation?(token.text) || negation_token?(token.text)
          prefix << (prefix.last + (barrier ? 1 : 0))
        end
      end

      def sentence_boundary_punctuation?(text)
        text.match?(SENTENCE_BOUNDARY_PUNCTUATION)
      end

      def negation_token?(text)
        normalized = TokenSimilarity.normalize(text)
        NEGATION_TOKENS.include?(normalized) || normalized.end_with?("n't", "n’t")
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
    # rubocop:enable Metrics/ClassLength

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
        in_range = tokens.select do |token|
          token.char_interval.start_pos >= range.begin && token.char_interval.end_pos <= range.end
        end
        in_range.flat_map { |token| split_boundary_punctuation(token) }
      end

      # UnicodeTokenizer intentionally keeps hyphenated words together for
      # tokenizer parity.  Fuzzy grounding additionally needs to recognize a
      # punctuation-boundary variant such as `New-York` vs `New York`, so split
      # dash punctuation only for the temporary alignment token stream.  The
      # resolver's canonical tokens remain unchanged for exact/token offsets.
      def split_boundary_punctuation(token)
        pieces = []
        cursor = 0
        token.text.to_enum(:scan, /\p{Pd}/u).each do
          match = Regexp.last_match
          append_alignment_token(token, pieces, cursor, match.begin(0))
          append_alignment_token(token, pieces, match.begin(0), match.end(0))
          cursor = match.end(0)
        end
        append_alignment_token(token, pieces, cursor, token.text.length)
        pieces
      end

      def append_alignment_token(token, pieces, start_pos, end_pos)
        return if start_pos >= end_pos

        pieces << Token.new(
          text: token.text[start_pos...end_pos],
          char_interval: CharInterval.new(
            start_pos: token.char_interval.start_pos + start_pos,
            end_pos: token.char_interval.start_pos + end_pos
          ),
          index: pieces.length
        )
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
