# frozen_string_literal: true

require "test_helper"

class RouterTest < LangExtractTest
  def test_router_loads_without_concrete_provider_adapters
    stdout, status = Open3.capture2e(
      RbConfig.ruby,
      "-Ilib",
      "-e",
      "require 'langextract/providers/router'; puts LangExtract::Providers::Router.new.names.inspect"
    )

    assert status.success?, stdout
    assert_includes stdout, "[]"
  end
end
