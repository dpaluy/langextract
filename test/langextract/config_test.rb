# frozen_string_literal: true

require "test_helper"
require "timeout"

class ConfigTest < LangExtractTest
  def test_config_initialization_is_thread_safe
    LangExtract.reset_configuration!
    object_ids = 20.times.map { Thread.new { LangExtract.config.object_id } }.map(&:value)

    assert_equal 1, object_ids.uniq.length
  end

  def test_configure_block_can_reenter_config
    configured = Timeout.timeout(5) do
      LangExtract.configure { LangExtract.config }
    end

    assert_same LangExtract.config, configured
  end
end
