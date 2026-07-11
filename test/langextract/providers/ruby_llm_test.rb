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

  private

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
