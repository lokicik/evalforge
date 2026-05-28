require "test_helper"

class EvaluationRunsSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user("one@example.com")
  end

  test "owner can create an evaluation run with a prompt version from the same project" do
    sign_in_as(@user)

    project = Project.create!(user: @user, name: "Owned Project")
    prompt = project.prompts.create!(name: "Owned Prompt")
    prompt_version = prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "Owned system prompt",
      user_prompt_template: "Hello {{name}}",
      description: "Owned prompt version"
    )
    test_case = project.test_cases.create!(
      input_variables: { name: "Ada" },
      expected_behavior: "Stay concise",
      difficulty: "medium"
    )

    assert_difference("EvaluationRun.count", 1) do
      post project_evaluation_runs_path(project), params: {
        evaluation_run: {
          name: "Safe run",
          prompt_version_id: prompt_version.id,
          llm_model: "manual"
        },
        test_case_ids: [test_case.id]
      }, headers: MODERN_BROWSER_HEADERS
    end

    run = EvaluationRun.order(:created_at).last
    assert_redirected_to project_evaluation_run_path(project, run)
    assert_equal prompt_version, run.prompt_version
    assert_equal project, run.project
  end

  private

  def create_user(email_address)
    User.create!(
      email_address: email_address,
      password: "password",
      password_confirmation: "password"
    )
  end
end
