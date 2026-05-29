require "test_helper"

class LlmProviderServiceTest < ActiveSupport::TestCase
  test "manual mode returns a mock response without making an OpenRouter request" do
    Net::HTTP.stub(:start, ->(*) { raise "should not call OpenRouter for manual mode" }) do
      result = LlmProviderService.call(
        system_prompt: "You are concise",
        user_prompt: "A friend ignored me",
        model_name: "manual"
      )

      assert_includes result[:content], "Your feelings of hurt and confusion are completely valid"
      assert_nil result[:cost]
    end
  end

  test "supported model labels map to OpenRouter model ids" do
    assert_equal "openai/gpt-4o", LlmProviderService.openrouter_model_for("gpt-4o")
    assert_equal "anthropic/claude-3.5-sonnet", LlmProviderService.openrouter_model_for("claude-3-5-sonnet")
    assert_nil LlmProviderService.openrouter_model_for("manual")
  end

  test "missing OpenRouter API key falls back to mock output and logs a warning" do
    warnings = []

    with_env("OPENROUTER_API_KEY" => nil) do
      Rails.logger.stub(:warn, ->(message) { warnings << message }) do
        Net::HTTP.stub(:start, ->(*) { raise "should not call OpenRouter without a key" }) do
          result = LlmProviderService.call(
            system_prompt: "Be helpful",
            user_prompt: "Customer support issue",
            model_name: "gpt-4o"
          )

          assert_includes result[:content], "Thank you for contacting customer support"
          assert_nil result[:cost]
        end
      end
    end

    assert_includes warnings, "OPENROUTER_API_KEY is blank. Falling back to a mocked response for gpt-4o."
  end

  test "successful OpenRouter responses are normalized into the app contract" do
    response_body = {
      choices: [
        {
          message: {
            content: "OpenRouter reply"
          }
        }
      ],
      usage: {
        prompt_tokens: 25,
        completion_tokens: 10,
        total_tokens: 35
      }
    }.to_json

    response = Struct.new(:code, :body).new("200", response_body)
    http = fake_http(response)
    request_body = nil

    with_env("OPENROUTER_API_KEY" => "test-key") do
      Net::HTTP.stub(:start, lambda { |*_args, **_kwargs, &block|
        response = block.call(http)
        request_body = http.last_request.body
        response
      }) do
        result = LlmProviderService.call(
          system_prompt: "Stay calm",
          user_prompt: "What should I say?",
          model_name: "claude-3-5-sonnet"
        )

        assert_equal "OpenRouter reply", result[:content]
        assert_equal 35, result[:tokens_used]
        assert_nil result[:cost]
      end
    end

    parsed_request = JSON.parse(request_body)
    assert_equal "anthropic/claude-3.5-sonnet", parsed_request["model"]
    assert_equal "system", parsed_request["messages"].first["role"]
    assert_equal "user", parsed_request["messages"].last["role"]
  end

  test "non-200 OpenRouter responses raise an error" do
    response = Struct.new(:code, :body).new("429", { error: { message: "rate limited" } }.to_json)

    with_env("OPENROUTER_API_KEY" => "test-key") do
      Net::HTTP.stub(:start, lambda { |*_args, **_kwargs, &block|
        block.call(fake_http(response))
      }) do
        error = assert_raises(RuntimeError) do
          LlmProviderService.call(
            system_prompt: "Stay calm",
            user_prompt: "What should I say?",
            model_name: "gpt-4o"
          )
        end

        assert_includes error.message, "OpenRouter API call failed with status 429"
      end
    end
  end

  private

  def with_env(overrides)
    original = overrides.keys.to_h { |key| [ key, ENV[key] ] }

    overrides.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def fake_http(response)
    Struct.new(:response, :last_request) do
      def request(req)
        self.last_request = req
        response
      end
    end.new(response)
  end
end
