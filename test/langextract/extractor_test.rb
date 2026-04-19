# frozen_string_literal: true

require "test_helper"

class ExtractorTest < LangExtractTest
  def setup
    super
    @fake_model_class = Struct.new(:output) do
      def infer(prompt:)
        raise "prompt missing text" unless prompt.include?("Apple")

        LangExtract::Providers::InferenceResult.new(text: output, raw: nil)
      end
    end
  end

  def test_extracts_single_annotated_document_through_public_api
    result = LangExtract.extract(
      text: "Apple reported revenue of $94.8 billion.",
      model: @fake_model_class.new({ extractions: [{ text: "Apple", extraction_class: "company" }] }.to_json),
      prompt_description: "Extract companies",
      prompt_validation: :off
    )

    assert_instance_of LangExtract::AnnotatedDocument, result
    assert_equal "Apple", result.extractions.first.text
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 5), result.extractions.first.char_interval
  end

  def test_extracts_document_collections_and_merges_duplicate_passes
    model = @fake_model_class.new({ extractions: [{ text: "Apple" }] }.to_json)
    documents = [LangExtract::Document.new(text: "Apple. Apple again.", id: "doc")]
    result = LangExtract.extract(
      documents: documents,
      model: model,
      prompt_description: "Extract company",
      extraction_passes: 2,
      prompt_validation: :off
    )

    assert_equal 1, result.length
    assert_equal 1, result.first.extractions.length
    assert_equal LangExtract::AlignmentStatus::EXACT, result.first.extractions.first.alignment_status
  end

  def test_validates_model_contract_at_construction
    error = assert_raises(LangExtract::InvalidModelConfigError) do
      LangExtract::Extractor.new(model: Object.new, prompt_description: "Extract")
    end

    assert_match(/#infer/, error.message)
  end

  def test_multi_pass_extraction_uses_distinct_prompts
    prompts = []
    model = Struct.new(:prompts) do
      def infer(prompt:)
        prompts << prompt
        LangExtract::Providers::InferenceResult.new(
          text: { extractions: [{ text: "Apple" }] }.to_json,
          raw: nil
        )
      end
    end.new(prompts)

    LangExtract.extract(
      text: "Apple reported revenue.",
      model: model,
      prompt_description: "Extract companies",
      extraction_passes: 2,
      prompt_validation: :off
    )

    assert_equal 2, prompts.length
    refute_equal prompts[0], prompts[1]
    assert_includes prompts[0], "Extraction pass: 1 of 2"
    assert_includes prompts[1], "Extraction pass: 2 of 2"
  end

  def test_exposes_allow_overlaps_through_public_api
    model = Struct.new(:output) do
      def infer(**)
        LangExtract::Providers::InferenceResult.new(text: output, raw: nil)
      end
    end.new({ extractions: [{ text: "Apple" }, { text: "Apple reported" }] }.to_json)

    result = LangExtract.extract(
      text: "Apple reported revenue.",
      model: model,
      prompt_description: "Extract companies",
      prompt_validation: :off,
      allow_overlaps: true
    )

    assert_equal 2, result.extractions.length
    assert_equal [LangExtract::AlignmentStatus::EXACT, LangExtract::AlignmentStatus::EXACT],
                 result.extractions.map(&:alignment_status)
  end

  def test_exposes_fuzzy_threshold_through_public_api
    model = Struct.new(:output) do
      def infer(**)
        LangExtract::Providers::InferenceResult.new(text: output, raw: nil)
      end
    end.new({ extractions: [{ text: "Jonathon Smith" }] }.to_json)

    result = LangExtract.extract(
      text: "Jonathan Smith works here.",
      model: model,
      prompt_description: "Extract names",
      prompt_validation: :off,
      fuzzy_threshold: 0.99
    )

    assert_equal LangExtract::AlignmentStatus::UNGROUNDED, result.extractions.first.alignment_status
  end
end
