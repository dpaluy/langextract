# Changelog

All notable changes to this project will be documented in this file.

## [0.4.0] - 2026-07-16

### Added
- `LangExtract::ModelConfig` now exposes opt-in `structured_output: true` (default `false`) for RubyLLM schema-constrained responses via `with_schema`. Non-boolean values are rejected, and schema-constrained Hash/Array responses are normalized back to JSON for the existing format handler. RubyLLM 1.16.0 or newer is required for this provider path. ([#13](https://github.com/dpaluy/langextract/pull/13))
- Fuzzy resolver alignment now operates on ordered token subsequences with per-token similarity, aggregate threshold, coverage and density gates, and sentence/negation barriers. Dash/space, standalone comma, apostrophe, and numeric-grouping variants ground symmetrically while preserving original offsets. One-edit tokens of 3–5 characters require another exact token in the same alignment, and every target-side negation must match an equivalent source negation. The default minimum density is 0.50. ([#14](https://github.com/dpaluy/langextract/pull/14))

### Changed
- Fuzzy alignment responsibilities are split across token-stream, similarity, index, planner, and aligner components. Indexed binary-search lookups replace repeated forward scans, and the historical 4,000-start truncation is no longer applied while candidate ordering and source offsets remain deterministic.
- Fuzzy planning skips search ranges larger than 20,000 tokens instead of building an unbounded target-by-source table. Exact alignment and preferred chunk-range fuzzy alignment still run; oversized ranges are skipped as a whole rather than truncating later candidate starts.
- Declared `logger` as a runtime dependency because it is no longer a default gem on Ruby 4.0; clean installations can load LangExtract without requiring applications to add it separately.

### Tests
- Added resolver grounding regressions for symmetric formatting variants, contextual short typos, coverage/density boundaries, and source- and target-side semantic barriers; complexity and performance guards for indexed alignment; expanded upstream parity fixtures; and provider/factory coverage for schema-constrained output.

## [0.3.0] - 2026-07-11

### Fixed
- Resolver: the case-insensitive alignment fallback derived offsets from a downcased copy of the source text, producing invalid intervals for characters whose lowercase form changes length (e.g. "İ") — an extraction could be marked `exact` while pointing at the wrong span. Matching now runs case-insensitively against the original text, so returned offsets are always valid.
- Resolver: the case-insensitive fallback found only the first occurrence; repeated extractions (e.g. two `alpha` against `ALPHA ALPHA`) now align to distinct spans instead of colliding on the first one.
- A bare `Hash` passed as `documents:` to `LangExtract.extract` (or to `LangExtract::IO.save_annotated_documents`) was silently split into key-value pairs and corrupted into multiple bogus documents. It is now treated as a single document.
- Chunking: a whitespace boundary exactly at the buffer limit produced chunks of `max_char_buffer + 1` characters. Split chunks now never exceed `max_char_buffer`.
- Extraction merging deduplicated by span/text/class only, discarding extractions that differed solely in `attributes` or `group_id`. Both are now part of the merge key; genuinely identical extractions still deduplicate (first wins).
- Value objects are now deeply immutable: nested hashes in `Extraction#attributes`, `Document#metadata`, and example data are frozen recursively (previously only the outer hash and arrays were frozen, so nested data could be mutated after construction).

### Changed
- **Breaking:** `LangExtract.extract` and `Extractor#initialize` now validate configuration at construction and raise `ArgumentError` for invalid values: `extraction_passes` and `max_char_buffer` must be Integers >= 1, `context_window_chars` an Integer >= 0, `fuzzy_threshold` Numeric within 0.0..1.0, `prompt_description` a non-empty String, `examples` enumerable (nil coerces to `[]`), and `format`/`prompt_validation` must be valid modes. Previously e.g. `extraction_passes: 0` silently made zero provider calls and returned empty results.
- **Breaking:** The minimum Ruby version is now 4.0.5 (`required_ruby_version = ">= 4.0.5"`), matching what CI actually tests. Previously the gem claimed `>= 4.0` without verifying older 4.0.x releases.
- Gem packaging now includes only git-tracked files (`git ls-files --cached`); untracked working-directory files can no longer leak into locally built gems. A packaging test guards the manifest.
- JSONL loading streams the file with `File.foreach` instead of reading it fully into memory.
- README: the source-grounding feature description no longer claims every extraction carries offsets — grounded extractions include character and token offsets, while ungrounded results retain an explicit alignment status.

Note: 0.2.0 was tagged but never published to RubyGems.org; 0.3.0 is the first published release containing both changelogs' changes since 0.1.0.

## [0.2.0] - 2026-07-11

### Added
- Provider error taxonomy under `LangExtract::Core::ProviderError`: `ProviderAuthError`, `ProviderRateLimitError`, `ProviderTimeoutError`, `ProviderResponseError`, and `ProviderConfigError`.
- Configured logging is now used: suppressed parse errors are logged at `warn` and per-document extraction summaries at `debug`. Set `logger` to `nil` to disable logging. `Rails.logger` is picked up only when actually present.

### Changed
- **Breaking:** The minimum Ruby version is now 4.0. CI tests Ruby 4.0.5.
- **Breaking:** Previously all provider errors were wrapped in `ProviderConfigError`. Now only recognized RubyLLM and timeout errors are mapped into the `ProviderError` taxonomy, with the original exception preserved as `#cause`; unknown errors such as `SocketError` and `Faraday::ConnectionFailed` propagate unchanged. `rescue LangExtract::ProviderConfigError` is no longer a catch-all; rescue `LangExtract::ProviderError` plus `StandardError` as needed.
- Improved resolver performance on large documents by reusing a resolver instance per document, pruning fuzzy-alignment candidates with similarity upper bounds, and exiting early on acceptable perfect matches. Fuzzy alignment now prefers matches inside the chunk's preferred interval before considering the rest of the document, which can select a chunk-local match over a marginally higher-scoring match elsewhere. This matches upstream LangExtract's chunk-local alignment semantics; previously all candidates were pooled and ranked globally by score.

### Fixed
- JSONL IO and fixture reads now force UTF-8 encoding, so the gem works under C/POSIX locales. Encoding failures raise `LangExtract::Core::IOFailure`.
- Lazy initialization of `LangExtract.config` and `Factory.router` is now thread-safe.

## [0.1.0] - 2026-04-19

### Added
- Initial Ruby gem scaffold for `langextract`.
- Core data contracts, tokenization, chunking, prompting, parsing, resolver, provider routing, JSONL IO, and visualization.
