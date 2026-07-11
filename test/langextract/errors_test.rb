# frozen_string_literal: true

require_relative "../test_helper"

class ErrorsTest < LangExtractTest
  def test_provider_errors_have_top_level_aliases
    assert_same LangExtract::Core::ProviderError, LangExtract::ProviderError
    assert_same LangExtract::Core::ProviderAuthError, LangExtract::ProviderAuthError
    assert_same LangExtract::Core::ProviderRateLimitError, LangExtract::ProviderRateLimitError
    assert_same LangExtract::Core::ProviderTimeoutError, LangExtract::ProviderTimeoutError
    assert_same LangExtract::Core::ProviderResponseError, LangExtract::ProviderResponseError
  end
end
