# frozen_string_literal: true

require "test_helper"

class FactoryTest < LangExtractTest
  def setup
    super
    @test_provider_class = Class.new(LangExtract::Providers::Base) do
      def infer(prompt:)
        LangExtract::Providers::InferenceResult.new(text: prompt, raw: nil)
      end
    end
  end

  def test_creates_providers_through_the_router
    LangExtract::Factory.router.register("test", @test_provider_class)
    config = LangExtract::ModelConfig.new(adapter: "test", model: "fixture")

    assert_kind_of @test_provider_class, LangExtract::Factory.create_model(config)
  end

  def test_validates_unknown_adapters
    config = LangExtract::ModelConfig.new(adapter: "missing", model: "fixture")

    assert_raises(LangExtract::InvalidModelConfigError) { LangExtract::Factory.create_model(config) }
  end

  def test_uses_langextract_model_default_without_credentials
    LangExtract.configure do |config|
      config.default_model = "configured"
    end
    config = LangExtract::ModelConfig.new

    assert_equal "configured", config.model
    assert_nil config.provider
  end

  def test_model_config_serialization_has_no_api_key_surface
    config = LangExtract::ModelConfig.new(adapter: "test", provider: "openai", model: "fixture")

    assert_equal "test", config.to_h["adapter"]
    assert_equal "openai", config.to_h["provider"]
    assert_equal "fixture", config.to_h["model"]
    refute_includes config.to_h.keys, "api_key"
  end

  def test_router_initialization_is_thread_safe
    LangExtract::Factory.instance_variable_set(:@router, nil)
    object_ids = 20.times.map { Thread.new { LangExtract::Factory.router.object_id } }.map(&:value)

    assert_equal 1, object_ids.uniq.length
  end

  def test_model_config_defaults_to_unconstrained_output
    config = LangExtract::ModelConfig.new(model: "fixture")

    assert_equal false, config.structured_output
  end

  def test_model_config_accepts_structured_output_true
    config = LangExtract::ModelConfig.new(model: "fixture", structured_output: true)

    assert_equal true, config.structured_output
  end

  def test_model_config_accepts_structured_output_false_explicitly
    config = LangExtract::ModelConfig.new(model: "fixture", structured_output: false)

    assert_equal false, config.structured_output
  end

  def test_model_config_rejects_non_boolean_structured_output
    ["true", 1, nil, :yes].each do |value|
      error = assert_raises(LangExtract::InvalidModelConfigError) do
        LangExtract::ModelConfig.new(model: "fixture", structured_output: value)
      end

      assert_includes error.message, "structured_output"
    end
  end

  def test_model_config_serialization_includes_structured_output
    config = LangExtract::ModelConfig.new(model: "fixture", structured_output: true)

    assert_equal true, config.to_h["structured_output"]
  end
end
