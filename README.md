# LangExtract

[![Gem Version](https://badge.fury.io/rb/langextract.svg)](https://badge.fury.io/rb/langextract)
[![CI](https://github.com/dpaluy/langextract/actions/workflows/ci.yml/badge.svg)](https://github.com/dpaluy/langextract/actions/workflows/ci.yml)

A Ruby gem for extracting structured information from unstructured text using LLMs with precise source grounding and interactive visualization.

Ruby port of [LangExtract](https://github.com/google/langextract) v1.2.1.

Use it when a Ruby or Rails app needs structured LLM output that can be traced back to exact source spans instead of ungrounded JSON blobs.

## Features

- **Source grounding** — every extraction includes character and token offsets back to the original text
- **Structured outputs** — deterministic, serializable result objects with alignment status
- **Long-document chunking** — sentence-aware chunking with sequential multi-pass extraction
- **Interactive visualization** — self-contained HTML highlighting of extraction spans
- **Format handling** — JSON and YAML output parsing with strict and lenient modes
- **Provider-agnostic** — pluggable LLM providers via [RubyLLM](https://github.com/crmne/ruby_llm)

## Requirements

- Ruby >= 3.4.5
- Tested on Ruby 3.4.5 and 4.0.2
- Optional live inference adapter: `ruby_llm` >= 1.0 when using `LangExtract::Factory.create_model`

## Installation

```bash
gem "langextract"
```

Provider calls go through RubyLLM. Add RubyLLM to applications that need live model inference:

```bash
bundle add ruby_llm
```

## Configuration

Configure RubyLLM the same way you already do in the host app. LangExtract does not own API keys or provider credentials:

```ruby
require "langextract"
require "ruby_llm"

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY")
  config.default_model = "gpt-4o-mini"
end
```

LangExtract has only a small optional configuration surface:

| Option | ENV variable | Default |
|--------|--------------|---------|
| `default_model` | `LANGEXTRACT_MODEL` | RubyLLM's `default_model` |

Per-call model configuration can override the RubyLLM model or provider without touching credentials:

```ruby
model = LangExtract::Factory.create_model(
  LangExtract::ModelConfig.new(
    model: "gpt-4o-mini",
    provider: "openai"
  )
)
```

If you omit `model`, RubyLLM's configured `default_model` is used.

### Rails

Create `config/initializers/langextract.rb`:

```ruby
RubyLLM.configure do |config|
  config.openai_api_key = Rails.application.credentials.dig(:openai, :api_key)
  config.default_model = "gpt-4o-mini"
end
```

## Usage

### Extract

Build a provider and extract grounded fields:

```ruby
model = LangExtract::Factory.create_model

result = LangExtract.extract(
  text: "Apple Inc. reported revenue of $94.8 billion for Q1 2024.",
  model: model,
  prompt_description: "Extract company financial data",
  examples: [
    LangExtract::ExampleData.new(
      text: "Microsoft earned $56.5 billion in Q2 2023.",
      extractions: [
        { text: "Microsoft", description: "company" },
        { text: "$56.5 billion", description: "revenue" },
        { text: "Q2 2023", description: "period" }
      ]
    )
  ]
)

result.extractions.each do |extraction|
  puts "#{extraction.text} (#{extraction.description}) #{extraction.char_interval}"
end
```

Return value access pattern:

```ruby
first = result.extractions.first
first.text
first.extraction_class
first.char_interval.start_pos
first.char_interval.end_pos
first.alignment_status
```

### Document collections

```ruby
documents = [
  LangExtract::Document.new(id: "q1", text: "Apple reported revenue."),
  LangExtract::Document.new(id: "q2", text: "Microsoft reported profit.")
]

annotated_documents = LangExtract.extract(
  documents: documents,
  model: model,
  prompt_description: "Extract company names",
  prompt_validation: :off
)
```

### Visualization

```ruby
html = LangExtract.visualize(result)
File.write("output.html", html)
```

`visualize` accepts a single `LangExtract::AnnotatedDocument`, an array of annotated documents, or a JSONL path.

### JSONL persistence

```ruby
LangExtract::IO.save_annotated_documents("results.jsonl", documents)
documents = LangExtract::IO.load_annotated_documents_jsonl("results.jsonl")
```

### Format schema validation

`FormatHandler` can validate normalized extractions against a small JSON-schema-like contract:

```ruby
schema = {
  required: %w[text extraction_class],
  properties: {
    text: { type: "string" },
    extraction_class: { type: "string" },
    attributes: { type: "object" }
  }
}

LangExtract::Core::FormatHandler.new.parse(model_output, schema: schema)
```

## Error handling

```ruby
begin
  LangExtract.extract(...)
rescue LangExtract::InvalidModelConfigError => e
  warn "Invalid model configuration: #{e.message}"
rescue LangExtract::ProviderConfigError => e
  warn "Provider failed: #{e.message}"
rescue LangExtract::PromptValidationError, LangExtract::FormatParsingError => e
  warn e.message
rescue LangExtract::AlignmentError => e
  warn "Could not ground extraction: #{e.message}"
rescue LangExtract::IOFailure => e
  warn "Could not read or write LangExtract data: #{e.message}"
end
```

## API reference

- Upstream project: [google/langextract](https://github.com/google/langextract)
- Ruby API docs: [rubydoc.info/gems/langextract](https://rubydoc.info/gems/langextract)

## Current parity status

This is a Ruby gem slice against the Google LangExtract v1.2.1. It includes the core public contracts, an optional RubyLLM-backed provider adapter, and fixture-backed tests for deterministic local behavior.

The upstream v1.2.1 tag was collected with pytest into `test/fixtures/upstream/v1_2_1_pytest_manifest.json`: 404 deterministic tests plus 11 live API tests and 4 Ollama integration tests. That collection does not match the older PRD snapshot count of 479 deterministic / 494 total, so the count discrepancy must be reconciled before a 1.0 parity claim.

Deferred v1+ items:

- Full expected-output parity conversion for every deterministic upstream case in the manifest
- External plugin discovery from installed Ruby gems
- Batch inference workflows
- Concurrent provider calls
- URL fetching

## Development

```bash
bundle install
bundle exec rake test
bundle exec rubocop
bundle exec rake build
bundle exec yard
```

Run a single test:

```bash
bundle exec ruby -Itest test/langextract/core/resolver_test.rb
bundle exec ruby -Itest test/langextract/core/resolver_test.rb -n test_aligns_exact_extraction_text_and_token_offsets
```

## Architecture

LangExtract follows a strict layered architecture:

```
Orchestrator
  ├── Prompting / Format Handling
  ├── Chunking / Tokenization
  ├── Resolver / Alignment          ← center of gravity
  ├── Annotation
  └── Provider (via RubyLLM)
```

**Core modules never depend on provider SDKs.** Provider output is normalized into an internal structure before reaching the resolver. The resolver handles exact and fuzzy alignment of extraction text back to source offsets — this is the most complex and critical module.

Differential test fixtures derived from the upstream Python library are the source of truth for behavioral parity.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/dpaluy/langextract.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
