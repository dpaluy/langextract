# frozen_string_literal: true

require_relative "config"
require_relative "core/errors"
require_relative "providers/router"
require_relative "providers/ruby_llm"

module LangExtract
  class ModelConfig
    attr_reader :adapter, :provider, :model, :options, :structured_output

    def initialize(adapter: "ruby_llm", provider: nil, model: nil, structured_output: false, **options)
      @adapter = adapter.to_s
      @provider = provider&.to_s
      @model = model || LangExtract.config.default_model
      @structured_output = structured_output
      @options = options.freeze

      validate!
      freeze
    end

    def to_h
      {
        "adapter" => adapter,
        "provider" => provider,
        "model" => model,
        "structured_output" => structured_output,
        "options" => options
      }
    end

    private

    def validate!
      raise Core::InvalidModelConfigError, "adapter is required" if adapter.empty?
      raise Core::InvalidModelConfigError, "provider cannot be blank" if provider == ""
      raise Core::InvalidModelConfigError, "model cannot be blank" if model == ""
      return if [true, false].include?(structured_output)

      raise Core::InvalidModelConfigError,
            "structured_output must be a boolean, got: #{structured_output.inspect}"
    end
  end

  module Factory
    ROUTER_MUTEX = Mutex.new

    module_function

    def create_model(config = ModelConfig.new)
      router.create(config)
    end

    def router
      ROUTER_MUTEX.synchronize { @router ||= default_router }
    end

    def reset_router!
      ROUTER_MUTEX.synchronize { @router = default_router }
    end

    def default_router
      Providers::Router.new.tap do |router|
        router.register("ruby_llm", Providers::RubyLLMProvider)
      end
    end
  end
end
