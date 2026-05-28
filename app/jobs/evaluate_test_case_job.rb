class EvaluateTestCaseJob < ApplicationJob
  queue_as :default

  # Enable retry for failed jobs
  retry_on StandardError, wait: 3.seconds, attempts: 2 do |job, error|
    # Mark the response as failed after all attempts
    if job.arguments.first
      resp = ModelResponse.find_by(id: job.arguments.first)
      resp&.update(status: "failed")
    end
  end

  def perform(model_response_id)
    model_response = ModelResponse.find(model_response_id)
    run = model_response.evaluation_run
    test_case = model_response.test_case
    prompt_version = run.prompt_version

    # Render system and user prompts
    system_prompt = prompt_version.system_prompt
    user_prompt = prompt_version.interpolate(test_case.input_variables)

    # Trigger LLM API call
    result = LlmProviderService.call(
      system_prompt: system_prompt,
      user_prompt: user_prompt,
      model_name: run.llm_model
    )

    # Save outputs
    model_response.update!(
      raw_response: result[:content],
      tokens_used: result[:tokens_used],
      cost: result[:cost],
      status: "completed"
    )

    # Check if all responses in this run are completed
    if run.model_responses.where.not(status: "completed").empty?
      run.update!(status: "completed")
    end
  end
end
