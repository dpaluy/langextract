# frozen_string_literal: true

require "erb"

require_relative "io"

module LangExtract
  class Visualization
    def render(input)
      annotated_documents = coerce_documents(input)

      render_page(annotated_documents)
    end

    private

    def render_page(annotated_documents)
      <<~HTML
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>LangExtract Visualization</title>
          <style>
            body { font-family: system-ui, sans-serif; line-height: 1.55; margin: 2rem; color: #1f2933; }
            main { max-width: 960px; margin: 0 auto; }
            mark { background: #ffe08a; border-radius: 0.2rem; padding: 0.05rem 0.15rem; }
            mark[data-status="fuzzy"] { background: #b7e4ff; }
            .label { color: #52606d; font-size: 0.85em; margin-left: 0.2rem; }
            pre { white-space: pre-wrap; font: inherit; }
          </style>
        </head>
        <body>
          <main>
            #{annotated_documents.map { |annotated| render_document(annotated) }.join("\n")}
          </main>
        </body>
        </html>
      HTML
    end

    def render_document(annotated)
      highlights = valid_extractions(annotated.extractions)

      <<~HTML
        <section>
          <h1>#{escape(annotated.id || 'Document')}</h1>
          <pre>#{highlight_text(annotated.text, highlights)}</pre>
        </section>
      HTML
    end

    def coerce_documents(input)
      return [input] if input.is_a?(Core::AnnotatedDocument)
      return input.to_a if document_collection?(input)

      loaded = LangExtract::IO.load_annotated_documents_jsonl(input.to_s)
      raise Core::IOFailure, "no annotated documents found in #{input}" if loaded.empty?

      loaded
    end

    def document_collection?(input)
      input.respond_to?(:to_a) && input.to_a.all?(Core::AnnotatedDocument)
    end

    def valid_extractions(extractions)
      occupied = []

      sorted = extractions.select(&:grounded?).sort_by { |extraction| extraction.char_interval.start_pos }

      sorted.filter_map do |extraction|
        next if occupied.any? { |interval| interval.overlaps?(extraction.char_interval) }

        occupied << extraction.char_interval
        extraction
      end
    end

    def highlight_text(text, extractions)
      cursor = 0
      output = +""

      extractions.each do |extraction|
        interval = extraction.char_interval
        output << escape(text[cursor...interval.start_pos])
        output << render_mark(extraction, text[interval.start_pos...interval.end_pos])
        cursor = interval.end_pos
      end

      output << escape(text[cursor..])
      output
    end

    def render_mark(extraction, content)
      label = extraction.description || extraction.extraction_class || "extraction"
      <<~HTML.delete("\n")
        <mark data-status="#{escape(extraction.alignment_status)}">#{escape(content)}<span class="label">#{escape(label)}</span></mark>
      HTML
    end

    def escape(value)
      ERB::Util.html_escape(value.to_s)
    end
  end
end
