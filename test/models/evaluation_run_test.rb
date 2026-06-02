require "test_helper"

class EvaluationRunTest < ActiveSupport::TestCase
  test "prompt_version must belong to the same project" do
    user = User.create!(
      email_address: "validation-one@example.com",
      password: "password",
      password_confirmation: "password"
    )
    other_user = User.create!(
      email_address: "validation-two@example.com",
      password: "password",
      password_confirmation: "password"
    )

    owned_project = Project.create!(user: user, name: "Owned Project")
    foreign_project = Project.create!(user: other_user, name: "Foreign Project")
    foreign_prompt = foreign_project.prompts.create!(name: "Foreign Prompt")
    foreign_prompt_version = foreign_prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "Top secret system prompt",
      user_prompt_template: "Classified {{name}}",
      description: "Foreign prompt version"
    )

    run = owned_project.evaluation_runs.build(
      name: "Blocked run",
      prompt_version: foreign_prompt_version,
      llm_model: "manual"
    )

    assert_not run.valid?
    assert_includes run.errors[:prompt_version], "must belong to this project"
  end

  test "public report template only references summary fields" do
    report_template = File.read(Rails.root.join("app/views/evaluation_runs/report.html.erb"))

    assert_includes report_template, "Public Summary Report"
    assert_includes report_template, "Sample Failures"
    assert_not_includes report_template, "system_prompt"
    assert_not_includes report_template, "user_prompt_template"
    assert_not_includes report_template, "input_variables"
    assert_not_includes report_template, "raw_response"
    assert_not_includes report_template, "review.notes"
  end

  test "refresh_status marks partial and failed runs correctly" do
    user = User.create!(
      email_address: "status-owner@example.com",
      password: "password",
      password_confirmation: "password"
    )
    project = Project.create!(user: user, name: "Status Project")
    prompt = project.prompts.create!(name: "Status Prompt")
    prompt_version = prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "System",
      user_prompt_template: "Hi {{name}}",
      description: "Version"
    )
    first_case = project.test_cases.create!(input_variables: { name: "Ada" }, expected_behavior: "Be concise", difficulty: "low")
    second_case = project.test_cases.create!(input_variables: { name: "Linus" }, expected_behavior: "Be concise", difficulty: "low")

    run = project.evaluation_runs.create!(
      name: "Status Run",
      prompt_version: prompt_version,
      llm_model: "gpt-4o",
      status: "running"
    )

    run.model_responses.create!(test_case: first_case, status: "completed", raw_response: "ok")
    run.model_responses.create!(test_case: second_case, status: "failed")

    run.refresh_status!

    assert_equal "partial", run.status
    assert_equal 1, run.completed_responses_count
    assert_equal 1, run.failed_responses_count

    run.model_responses.update_all(status: "failed")
    run.refresh_status!

    assert_equal "failed", run.status
  end
end
