require "test_helper"

class EvaluationOperationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = create_user("ops-owner@example.com")
    clear_enqueued_jobs
  end

  test "owner can retry failed model responses from the run detail page" do
    sign_in_as(@user)

    project, run = build_project_run(llm_model: "gpt-4o", status: "partial")
    response = run.model_responses.create!(
      test_case: project.test_cases.first,
      raw_response: "failed output",
      status: "failed",
      tokens_used: 111,
      cost: BigDecimal("0.0100")
    )
    response.create_review!(reviewer: @user, status: "failed", notes: "Needs retry")
    response.scores.create!(rubric_criterion: project.rubrics.first.rubric_criteria.first, value: 1, feedback: "Bad")

    assert_enqueued_jobs 1, only: EvaluateTestCaseJob do
      post retry_failed_project_evaluation_run_path(project, run), headers: MODERN_BROWSER_HEADERS
    end

    assert_redirected_to project_evaluation_run_path(project, run)
    response.reload
    run.reload

    assert_equal "pending", response.status
    assert_nil response.raw_response
    assert_nil response.tokens_used
    assert_equal "running", run.status
    assert_not response.reviewed?
    assert_empty response.scores
  end

  test "owner can rerun an evaluation run with the same test cases" do
    sign_in_as(@user)

    project, run = build_project_run(llm_model: "manual", status: "completed")
    first_case = project.test_cases.first
    second_case = project.test_cases.second

    run.model_responses.create!(test_case: first_case, raw_response: "first", status: "completed", tokens_used: 50, cost: BigDecimal("0"))
    run.model_responses.create!(test_case: second_case, raw_response: "second", status: "completed", tokens_used: 55, cost: BigDecimal("0"))

    assert_difference("EvaluationRun.count", 1) do
      post rerun_project_evaluation_run_path(project, run), headers: MODERN_BROWSER_HEADERS
    end

    rerun = EvaluationRun.order(:created_at).last
    assert_redirected_to project_evaluation_run_path(project, rerun)
    assert_equal run.prompt_version, rerun.prompt_version
    assert_equal run.llm_model, rerun.llm_model
    assert_equal run.test_case_ids.sort, rerun.test_case_ids.sort
    assert_equal "completed", rerun.status
  end

  test "projects index supports project search" do
    sign_in_as(@user)

    Project.create!(user: @user, name: "Customer Support Bot", description: "Support")
    Project.create!(user: @user, name: "Empathy Benchmark", description: "Emotion")

    get projects_path(project_query: "Support"), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_includes response.body, "Customer Support Bot"
    assert_not_includes response.body, "Empathy Benchmark"
  end

  test "project dashboard supports prompt search and run filters" do
    sign_in_as(@user)

    project, matched_run = build_project_run(llm_model: "gpt-4o", status: "partial", project_name: "Filter Project")
    other_prompt = project.prompts.create!(name: "Other Prompt", description: "Ignore me")
    other_prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "Other system",
      user_prompt_template: "Other {{name}}",
      description: "Other version"
    )

    project.evaluation_runs.create!(
      name: "Manual baseline",
      prompt_version: other_prompt.prompt_versions.first,
      llm_model: "manual",
      status: "completed",
      created_at: 10.days.ago
    )

    get project_path(project, tab: "prompts", prompt_query: "Ops Prompt"), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_includes response.body, "Ops Prompt"
    assert_not_includes response.body, "Other Prompt"

    get project_path(
      project,
      tab: "evaluation_runs",
      run_query: "Ops Run",
      run_status: "partial",
      run_model: "gpt-4o",
      run_from: 2.days.ago.to_date.iso8601,
      run_to: Date.current.iso8601
    ), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_includes response.body, matched_run.name
    assert_not_includes response.body, "Manual baseline"
    assert_includes response.body, "partial"
  end

  private

  def build_project_run(llm_model:, status:, project_name: "Ops Project")
    project = Project.create!(user: @user, name: project_name, description: "Operations")
    prompt = project.prompts.create!(name: "Ops Prompt", description: "Prompt")
    prompt_version = prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "System prompt",
      user_prompt_template: "Hello {{name}}",
      description: "Version"
    )
    project.test_cases.create!(input_variables: { name: "Ada" }, expected_behavior: "Stay concise", difficulty: "medium")
    project.test_cases.create!(input_variables: { name: "Linus" }, expected_behavior: "Stay concise", difficulty: "medium")
    rubric = project.rubrics.create!(name: "Ops Rubric", description: "Checks")
    rubric.rubric_criteria.create!(name: "Accuracy", weight: 3, description: "Accurate")

    run = project.evaluation_runs.create!(
      name: "Ops Run",
      prompt_version: prompt_version,
      llm_model: llm_model,
      status: status
    )

    [ project, run ]
  end

  def create_user(email_address)
    User.create!(
      email_address: email_address,
      password: "password",
      password_confirmation: "password"
    )
  end
end
