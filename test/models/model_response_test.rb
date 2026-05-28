require "test_helper"

class ModelResponseTest < ActiveSupport::TestCase
  test "pending_review_for_user only counts completed unreviewed responses for that user" do
    user = User.create!(
      email_address: "scope-one@example.com",
      password: "password",
      password_confirmation: "password"
    )
    other_user = User.create!(
      email_address: "scope-two@example.com",
      password: "password",
      password_confirmation: "password"
    )

    owned_project = Project.create!(user: user, name: "Owned Project")
    foreign_project = Project.create!(user: other_user, name: "Foreign Project")

    owned_run = owned_project.evaluation_runs.create!(
      name: "Owned Run",
      prompt_version: create_prompt_version_for(owned_project, "Owned Prompt"),
      llm_model: "manual",
      status: "completed"
    )
    foreign_run = foreign_project.evaluation_runs.create!(
      name: "Foreign Run",
      prompt_version: create_prompt_version_for(foreign_project, "Foreign Prompt"),
      llm_model: "manual",
      status: "completed"
    )

    owned_pending = owned_run.model_responses.create!(
      test_case: create_test_case_for(owned_project, "owned"),
      raw_response: "Owned pending response",
      status: "completed"
    )
    owned_reviewed = owned_run.model_responses.create!(
      test_case: create_test_case_for(owned_project, "reviewed"),
      raw_response: "Owned reviewed response",
      status: "completed"
    )
    owned_reviewed.create_review!(reviewer: user, status: "passed", notes: "Reviewed")

    foreign_pending = foreign_run.model_responses.create!(
      test_case: create_test_case_for(foreign_project, "foreign"),
      raw_response: "Foreign pending response",
      status: "completed"
    )

    assert_equal [owned_pending.id], ModelResponse.pending_review_for_user(user).pluck(:id)
    assert_equal [foreign_pending.id], ModelResponse.pending_review_for_user(other_user).pluck(:id)
  end

  private

  def create_prompt_version_for(project, prompt_name)
    prompt = project.prompts.create!(name: prompt_name)
    prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "#{prompt_name} system",
      user_prompt_template: "#{prompt_name} template {{value}}",
      description: "#{prompt_name} description"
    )
  end

  def create_test_case_for(project, value)
    project.test_cases.create!(
      input_variables: { value: value },
      expected_behavior: "Keep it concise",
      difficulty: "medium"
    )
  end
end
