# frozen_string_literal: true

require "test_helper"

class PromptingTest < LangExtractTest
  def test_renders_examples_additional_context_and_source_context_windows
    document = LangExtract::Document.new(text: "Before. Apple reported revenue. After.", id: "doc")
    chunk = LangExtract::Core::Chunk.new(
      text: "Apple reported revenue.",
      char_interval: LangExtract::CharInterval.new(start_pos: 8, end_pos: 31),
      token_interval: nil,
      index: 0,
      document_id: "doc"
    )
    example = LangExtract::ExampleData.new(
      text: "Microsoft reported profit.",
      extractions: [{ text: "Microsoft", extraction_class: "company" }]
    )

    prompt = LangExtract::Core::PromptBuilder.new(validation_mode: :error).build(
      document: document,
      chunk: chunk,
      prompt_description: "Extract companies",
      examples: [example],
      additional_context: "Financial filings",
      context_window_chars: 8
    )

    assert_includes prompt, "Task: Extract companies"
    assert_includes prompt, "Additional context: Financial filings"
    assert_includes prompt, "Microsoft"
    assert_includes prompt, "Context before"
  end

  def test_raises_when_prompt_validation_is_in_error_mode
    document = LangExtract::Document.new(text: "Text", id: "doc")
    chunk = LangExtract::Core::Chunk.new(
      text: "Text",
      char_interval: LangExtract::CharInterval.new(start_pos: 0, end_pos: 4),
      token_interval: nil,
      index: 0,
      document_id: "doc"
    )
    bad_example = LangExtract::ExampleData.new(text: "No match", extractions: [{ text: "Missing" }])

    error = assert_raises(LangExtract::PromptValidationError) do
      LangExtract::Core::PromptBuilder.new(validation_mode: :error).build(
        document: document,
        chunk: chunk,
        prompt_description: "Extract",
        examples: [bad_example]
      )
    end

    assert_match(/not present/, error.message)
  end
end
