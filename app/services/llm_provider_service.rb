require "net/http"
require "json"

class LlmProviderService
  MODEL_CATALOG = {
    "manual" => {
      label: "Manual Grading",
      openrouter_model: nil
    },
    "gpt-4o" => {
      label: "GPT-4o via OpenRouter",
      openrouter_model: "openai/gpt-4o"
    },
    "claude-3-5-sonnet" => {
      label: "Claude 3.5 Sonnet via OpenRouter",
      openrouter_model: "anthropic/claude-3.5-sonnet"
    }
  }.freeze

  OPENROUTER_URI = URI("https://openrouter.ai/api/v1/chat/completions")

  def self.call(system_prompt:, user_prompt:, model_name:)
    return call_mock(system_prompt, user_prompt, model_name) if model_name == "manual"

    call_openrouter(system_prompt, user_prompt, model_name)
  end

  def self.supported_model_keys
    MODEL_CATALOG.keys
  end

  def self.options_for_select
    MODEL_CATALOG.map { |key, config| [ config[:label], key ] }
  end

  def self.openrouter_model_for(model_name)
    MODEL_CATALOG.dig(model_name, :openrouter_model)
  end

  private

  def self.call_openrouter(system_prompt, user_prompt, model_name)
    api_key = ENV["OPENROUTER_API_KEY"]
    openrouter_model = openrouter_model_for(model_name)

    unless openrouter_model
      raise ArgumentError, "Unsupported model selection: #{model_name.inspect}"
    end

    if api_key.blank?
      Rails.logger.warn "OPENROUTER_API_KEY is blank. Falling back to a mocked response for #{model_name}."
      return call_mock(system_prompt, user_prompt, model_name)
    end

    req = Net::HTTP::Post.new(OPENROUTER_URI)
    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{api_key}"

    req.body = {
      model: openrouter_model,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt }
      ],
      temperature: 0.7
    }.to_json

    res = Net::HTTP.start(OPENROUTER_URI.hostname, OPENROUTER_URI.port, use_ssl: true) { |http| http.request(req) }
    data = JSON.parse(res.body)

    if res.code == "200"
      {
        content: data.dig("choices", 0, "message", "content"),
        tokens_used: data.dig("usage", "total_tokens"),
        cost: nil
      }
    else
      raise "OpenRouter API call failed with status #{res.code}: #{data}"
    end
  end

  def self.call_mock(system_prompt, user_prompt, model_name)
    # Simulate network delay for real-feeling job status updates
    sleep(1.2)

    # Generate smart response based on keywords
    content = if user_prompt.downcase.include?("ignored")
      "It can be incredibly tough when a friend seems to shut you out or ignore you. Your feelings of hurt and confusion are completely valid. " \
      "Sometimes friends pull back due to personal stress, busyness, or anxiety, rather than active hostility. " \
      "I'd suggest giving them a little breathing room, then reaching out with a simple, low-pressure check-in. Avoid overreacting or jumping to negative assumptions."
    elsif user_prompt.downcase.include?("support")
      "Thank you for contacting customer support. I understand you are having issues with your subscription. " \
      "Let me look into your account details right away and resolve this for you. I apologize for any inconvenience caused."
    else
      "This is an automated mock evaluation response for model: #{model_name}. " \
      "System Prompt constraints: \"#{system_prompt[0..60]}...\" " \
      "User Prompt context: \"#{user_prompt[0..60]}...\""
    end

    prompt_tokens = system_prompt.split.size + user_prompt.split.size + 20
    completion_tokens = content.split.size + 10

    {
      content: content,
      tokens_used: prompt_tokens + completion_tokens,
      cost: nil
    }
  end
end
