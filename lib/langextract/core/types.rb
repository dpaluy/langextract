# frozen_string_literal: true

require_relative "errors"

module LangExtract
  module Core
    module AlignmentStatus
      EXACT = "exact"
      FUZZY = "fuzzy"
      UNGROUNDED = "ungrounded"
      OVERLAP = "overlap"
      ERROR = "error"

      ALL = [EXACT, FUZZY, UNGROUNDED, OVERLAP, ERROR].freeze

      def self.valid?(status)
        ALL.include?(status)
      end
    end
  end
end
