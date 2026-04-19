# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "json"
require "langextract"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "stringio"
require "tmpdir"

class LangExtractTest < Minitest::Test
  def setup
    LangExtract.reset_configuration!
  end
end
