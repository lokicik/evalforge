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
end
