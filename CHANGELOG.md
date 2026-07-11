# Changelog

All notable changes to this project will be documented in this file.

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
