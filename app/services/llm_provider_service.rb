require "net/http"
require "json"
require "bigdecimal"

class LlmProviderService
  def self.call(system_prompt:, user_prompt:, model_name:)
    # Choose provider
    if model_name.include?("gpt")
      call_openai(system_prompt, user_prompt, model_name)
    elsif model_name.include?("claude")
      call_anthropic(system_prompt, user_prompt, model_name)
    else
      call_mock(system_prompt, user_prompt, model_name)
    end
  end

  private

  def self.call_openai(system_prompt, user_prompt, model_name)
    api_key = ENV["OPENAI_API_KEY"]
    if api_key.blank?
      Rails.logger.warn "OPENAI_API_KEY is blank. Falling back to mocked GPT response."
      return call_mock(system_prompt, user_prompt, model_name)
    end

    # Real OpenAI call using Net::HTTP to keep dependencies zero/minimal and highly secure!
    uri = URI("https://api.openai.com/v1/chat/completions")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{api_key}"
    
    req.body = {
      model: model_name,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt }
      ],
      temperature: 0.7
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.code == "200"
      data = JSON.parse(res.body)
      {
        content: data.dig("choices", 0, "message", "content"),
        tokens_used: data.dig("usage", "total_tokens"),
        cost: calculate_cost(model_name, data.dig("usage", "prompt_tokens"), data.dig("usage", "completion_tokens"))
      }
    else
      raise "OpenAI API call failed with status #{res.code}: #{res.body}"
    end
  end

  def self.call_anthropic(system_prompt, user_prompt, model_name)
    api_key = ENV["ANTHROPIC_API_KEY"]
    if api_key.blank?
      Rails.logger.warn "ANTHROPIC_API_KEY is blank. Falling back to mocked Claude response."
      return call_mock(system_prompt, user_prompt, model_name)
    end

    # Real Anthropic call using Net::HTTP
    uri = URI("https://api.openai.com/v1/chat/completions") # or actual Anthropic API. Using standard Anthropic REST API:
    uri = URI("https://api.anthropic.com/v1/messages")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["x-api-key"] = api_key
    req["anthropic-version"] = "2023-06-01"

    req.body = {
      model: model_name == "claude-3-5-sonnet" ? "claude-3-5-sonnet-20241022" : model_name,
      system: system_prompt,
      messages: [
        { role: "user", content: user_prompt }
      ],
      max_tokens: 1024
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.code == "200"
      data = JSON.parse(res.body)
      {
        content: data.dig("content", 0, "text"),
        tokens_used: data.dig("usage", "input_tokens").to_i + data.dig("usage", "output_tokens").to_i,
        cost: calculate_cost(model_name, data.dig("usage", "input_tokens"), data.dig("usage", "output_tokens"))
      }
    else
      raise "Anthropic API call failed with status #{res.code}: #{res.body}"
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
      cost: calculate_cost(model_name, prompt_tokens, completion_tokens)
    }
  end

  def self.calculate_cost(model_name, prompt_tokens, completion_tokens)
    # Standard pricing in USD per 1M tokens
    case model_name
    when "gpt-4o"
      prompt_cost = (prompt_tokens.to_f / 1_000_000) * 5.0
      comp_cost = (completion_tokens.to_f / 1_000_000) * 15.0
    when "claude-3-5-sonnet"
      prompt_cost = (prompt_tokens.to_f / 1_000_000) * 3.0
      comp_cost = (completion_tokens.to_f / 1_000_000) * 15.0
    else
      prompt_cost = (prompt_tokens.to_f / 1_000_000) * 0.1
      comp_cost = (completion_tokens.to_f / 1_000_000) * 0.2
    end
    BigDecimal(prompt_cost + comp_cost, 8)
  end
end
