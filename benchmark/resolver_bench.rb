# frozen_string_literal: true

require "benchmark"
require "langextract"

text = Array.new(30_000) { |index| "word#{index}" }.join(" ").slice(0, 200_000)
extraction = "A sixty character extraction deliberately absent from generated text."
resolver = LangExtract::Core::Resolver.new(text: text)

elapsed = Benchmark.realtime do
  resolver.resolve([{ "text" => extraction }])
end

puts "Document bytes: #{text.bytesize}"
puts "Extraction characters: #{extraction.length}"
puts format("Resolver elapsed: %.6f seconds", elapsed)
