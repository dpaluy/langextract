# frozen_string_literal: true

require "test_helper"

class TokenizerTest < LangExtractTest
  def test_regex_tokenizer_preserves_offsets_for_whitespace_tokens
    tokens = LangExtract::Core::RegexTokenizer.new.tokenize("Alpha  beta\nGamma")

    assert_equal %w[Alpha beta Gamma], tokens.map(&:text)
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 5), tokens[0].char_interval
    assert_equal LangExtract::CharInterval.new(start_pos: 7, end_pos: 11), tokens[1].char_interval
    assert_equal LangExtract::CharInterval.new(start_pos: 12, end_pos: 17), tokens[2].char_interval
  end

  def test_preserves_character_offsets_across_unicode_text
    tokens = LangExtract::Core::UnicodeTokenizer.new.tokenize("Café costs €5.")

    assert_equal ["Café", "costs", "€", "5", "."], tokens.map(&:text)
    assert_equal LangExtract::CharInterval.new(start_pos: 0, end_pos: 4), tokens.first.char_interval
    assert_equal LangExtract::CharInterval.new(start_pos: 11, end_pos: 12), tokens[2].char_interval
  end
end
