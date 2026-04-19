# frozen_string_literal: true

require "test_helper"

class PromptValidationTest < LangExtractTest
  def test_off_mode_skips_invalid_examples
    validator = LangExtract::Core::PromptValidation.new(mode: :off)
    bad_example = LangExtract::ExampleData.new(text: "No match", extractions: [{ text: "   " }])

    assert_nil validator.validate!([bad_example])
  end

  def test_empty_examples_are_valid
    validator = LangExtract::Core::PromptValidation.new(mode: :error)

    assert_nil validator.validate!([])
  end

  def test_whitespace_only_extraction_text_is_invalid
    validator = LangExtract::Core::PromptValidation.new(mode: :error)
    bad_example = LangExtract::ExampleData.new(text: "Patient text", extractions: [{ text: "   " }])

    error = assert_raises(LangExtract::PromptValidationError) { validator.validate!([bad_example]) }

    assert_match(/text is empty/, error.message)
  end

  def test_warning_mode_writes_to_warning_io
    warning_io = StringIO.new
    validator = LangExtract::Core::PromptValidation.new(mode: :warning, warning_io: warning_io)
    bad_example = LangExtract::ExampleData.new(text: "Patient text", extractions: [{ text: "Missing" }])

    validator.validate!([bad_example])

    assert_match(/failed validation/, warning_io.string)
  end
end
