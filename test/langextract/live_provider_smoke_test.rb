# frozen_string_literal: true

require "test_helper"

class LiveProviderSmokeTest < LangExtractTest
  def test_runs_env_gated_openai_ruby_llm_extraction_smoke_test
    api_key = ENV.fetch("OPENAI_API_KEY", nil)
    unless ENV["LANGEXTRACT_LIVE_OPENAI"] == "1" && api_key
      skip "set LANGEXTRACT_LIVE_OPENAI=1 and OPENAI_API_KEY to run"
    end

    require "ruby_llm"
    RubyLLM.configure do |config|
      config.openai_api_key = api_key
      config.default_model = ENV.fetch("LANGEXTRACT_LIVE_MODEL", config.default_model)
    end

    result = LangExtract.extract(
      text: "Apple reported revenue of $94.8 billion.",
      model: LangExtract::Factory.create_model(LangExtract::ModelConfig.new(provider: "openai")),
      prompt_description: "Extract company names as JSON.",
      prompt_validation: :off,
      suppress_parse_errors: false
    )

    assert_includes result.extractions.map(&:text), "Apple"
  end
end
