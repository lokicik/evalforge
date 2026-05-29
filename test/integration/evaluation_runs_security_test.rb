require "test_helper"

class EvaluationRunsSecurityTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = create_user("one@example.com")
    clear_enqueued_jobs
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

  test "non-manual runs keep the curated label and enqueue evaluation jobs" do
    sign_in_as(@user)

    project = Project.create!(user: @user, name: "Queued Project")
    prompt = project.prompts.create!(name: "Queued Prompt")
    prompt_version = prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "Owned system prompt",
      user_prompt_template: "Hello {{name}}",
      description: "Owned prompt version"
    )
    first_case = project.test_cases.create!(
      input_variables: { name: "Ada" },
      expected_behavior: "Stay concise",
      difficulty: "medium"
    )
    second_case = project.test_cases.create!(
      input_variables: { name: "Linus" },
      expected_behavior: "Stay concise",
      difficulty: "medium"
    )

    assert_difference("EvaluationRun.count", 1) do
      assert_enqueued_jobs 2, only: EvaluateTestCaseJob do
        post project_evaluation_runs_path(project), params: {
          evaluation_run: {
            name: "Queued run",
            prompt_version_id: prompt_version.id,
            llm_model: "gpt-4o"
          },
          test_case_ids: [ first_case.id, second_case.id ]
        }, headers: MODERN_BROWSER_HEADERS
      end
    end

    run = EvaluationRun.order(:created_at).last
    assert_redirected_to project_evaluation_run_path(project, run)
    assert_equal "gpt-4o", run.llm_model
    assert_equal "running", run.status
    assert_equal 2, run.model_responses.where(status: "pending").count
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
