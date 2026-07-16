# frozen_string_literal: true

require "test_helper"

original_verbose = $VERBOSE
$VERBOSE = nil
require "ruby_llm"
$VERBOSE = original_verbose

class RubyLLMProviderTest < LangExtractTest
  def test_maps_ruby_llm_errors_and_preserves_the_cause
    mappings = {
      RubyLLM::UnauthorizedError => LangExtract::Core::ProviderAuthError,
      RubyLLM::ConfigurationError => LangExtract::Core::ProviderConfigError,
      RubyLLM::RateLimitError => LangExtract::Core::ProviderRateLimitError,
      RubyLLM::ServerError => LangExtract::Core::ProviderResponseError
    }

    mappings.each do |original_class, mapped_class|
      original = original_class.allocate
      error = assert_raises(mapped_class) { infer_with_error(original) }

      assert_same original, error.cause
      assert_includes error.message, original.message
    end
  end

  def test_maps_timeout_errors_and_preserves_the_cause
    original = Timeout::Error.new("request timed out")
    error = assert_raises(LangExtract::Core::ProviderTimeoutError) { infer_with_error(original) }

    assert_same original, error.cause
    assert_includes error.message, original.message
  end

  def test_propagates_unrelated_standard_errors
    original = StandardError.new("unrelated")
    error = assert_raises(StandardError) { infer_with_error(original) }

    assert_same original, error
  end

  def test_propagates_anonymous_error_classes
    original = Class.new(StandardError).new("anonymous")
    error = assert_raises(original.class) { infer_with_error(original) }

    assert_same original, error
  end

  # --- structured_output: enabled path ---

  def test_calls_with_schema_before_ask_when_structured_output_enabled
    chat = FakeChat.new('{"extractions":[{"text":"hello"}]}')
    provider = LangExtract::Providers::RubyLLMProvider.new(
      LangExtract::ModelConfig.new(model: "test", structured_output: true)
    )

    stub_ruby_llm_chat(chat) { provider.infer(prompt: "test") }

    assert_includes chat.call_sequence, :with_schema
    assert_includes chat.call_sequence, :ask
    assert_operator chat.call_sequence.index(:with_schema), :<, chat.call_sequence.index(:ask)
  end

  def test_does_not_call_with_schema_by_default
    chat = FakeChat.new('{"extractions":[]}')
    provider = LangExtract::Providers::RubyLLMProvider.new(
      LangExtract::ModelConfig.new(model: "test")
    )

    stub_ruby_llm_chat(chat) { provider.infer(prompt: "test") }

    refute_includes chat.call_sequence, :with_schema
    assert_includes chat.call_sequence, :ask
  end

  def test_does_not_call_with_schema_when_explicitly_disabled
    chat = FakeChat.new('{"extractions":[]}')
    provider = LangExtract::Providers::RubyLLMProvider.new(
      LangExtract::ModelConfig.new(model: "test", structured_output: false)
    )

    stub_ruby_llm_chat(chat) { provider.infer(prompt: "test") }

    refute_includes chat.call_sequence, :with_schema
  end

  def test_passes_internal_extraction_schema_to_with_schema
    chat = FakeChat.new('{"extractions":[]}')
    provider = LangExtract::Providers::RubyLLMProvider.new(
      LangExtract::ModelConfig.new(model: "test", structured_output: true)
    )

    stub_ruby_llm_chat(chat) { provider.infer(prompt: "test") }

    schema = chat.schema
    refute_nil schema
    assert_equal "object", schema["type"]
    assert_includes schema["required"], "extractions"
    assert_internal_extraction_schema(schema)
  end

  def test_schema_constrained_hash_response_flows_through_format_handler
    hash_content = {
      "extractions" => [
        { "text" => "Apple", "extraction_class" => "company", "description" => "entity" }
      ]
    }
    chat = FakeChat.new(hash_content)
    provider = LangExtract::Providers::RubyLLMProvider.new(
      LangExtract::ModelConfig.new(model: "test", structured_output: true)
    )

    result = stub_ruby_llm_chat(chat) { provider.infer(prompt: "test") }

    assert_kind_of LangExtract::Providers::InferenceResult, result

    format_handler = LangExtract::Core::FormatHandler.new
    extractions = format_handler.parse(result.text)
    assert_equal "Apple", extractions.first["text"]
    assert_equal "company", extractions.first["extraction_class"]
    assert_equal "entity", extractions.first["description"]
  end

  # --- Fake infrastructure ---

  FakeResponse = Data.define(:content)

  class FakeChat
    attr_reader :schema, :call_sequence

    def initialize(response_content)
      @response_content = response_content
      @call_sequence = []
    end

    def with_schema(schema)
      @schema = schema
      @call_sequence << :with_schema
      self
    end

    def ask(_prompt = nil)
      @call_sequence << :ask
      FakeResponse.new(@response_content)
    end
  end

  private

  def assert_internal_extraction_schema(schema)
    item_schema = schema.dig("properties", "extractions", "items")
    item_props = item_schema["properties"]
    assert_equal "string", item_props["text"]["type"]
    assert_includes item_schema["required"], "text"
    assert_equal "string", item_props["extraction_class"]["type"]
    assert_equal "string", item_props["description"]["type"]
    assert_equal "object", item_props["attributes"]["type"]
    assert_equal "string", item_props["group_id"]["type"]
  end

  def stub_ruby_llm_chat(chat)
    original_chat = RubyLLM.method(:chat)
    without_warnings { RubyLLM.define_singleton_method(:chat) { |**| chat } }
    yield
  ensure
    without_warnings { RubyLLM.define_singleton_method(:chat, original_chat) } if original_chat
  end

  def infer_with_error(error)
    provider = LangExtract::Providers::RubyLLMProvider.new(LangExtract::ModelConfig.new(model: "test"))
    original_chat = RubyLLM.method(:chat)
    without_warnings { RubyLLM.define_singleton_method(:chat) { |**| raise error } }
    provider.infer(prompt: "prompt")
  ensure
    without_warnings { RubyLLM.define_singleton_method(:chat, original_chat) } if original_chat
  end

  def without_warnings
    original_verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = original_verbose
  end
end
