require "test_helper"

class ProjectAnalyticsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("analytics-ui-owner@example.com")
    @other_user = create_user("analytics-ui-other@example.com")
  end

  test "owner can load project analytics and compare a selected prompt within filters" do
    sign_in_as(@owner)

    project = Project.create!(user: @owner, name: "Analytics UI Project", description: "Desc")
    prompt = project.prompts.create!(name: "Support Prompt", description: "Prompt")
    prompt_version = prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "System",
      user_prompt_template: "Hi {{name}}",
      description: "Version one"
    )
    other_prompt = project.prompts.create!(name: "Other Prompt", description: "Other")
    other_version = other_prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "Other",
      user_prompt_template: "Other {{name}}",
      description: "Other version"
    )
    first_case = project.test_cases.create!(input_variables: { name: "Ada" }, expected_behavior: "Helpful", difficulty: "medium", tags: "support")
    second_case = project.test_cases.create!(input_variables: { name: "Linus" }, expected_behavior: "Helpful", difficulty: "high", tags: "edge")
    rubric = project.rubrics.create!(name: "UI Rubric", description: "Checks")
    empathy = rubric.rubric_criteria.create!(name: "Empathy", weight: 3, description: "Empathetic")

    run = project.evaluation_runs.create!(
      name: "Scoped Run",
      prompt_version: prompt_version,
      llm_model: "gpt-4o",
      status: "completed",
      created_at: 1.day.ago
    )
    response = run.model_responses.create!(test_case: first_case, raw_response: "Answer", status: "completed", tokens_used: 100, cost: BigDecimal("0.0100"))
    response.create_review!(reviewer: @owner, status: "failed", notes: "Weak")
    response.scores.create!(rubric_criterion: empathy, value: 2, feedback: "Weak empathy")

    other_run = project.evaluation_runs.create!(
      name: "Filtered Out Run",
      prompt_version: other_version,
      llm_model: "manual",
      status: "completed",
      created_at: 1.day.ago
    )
    other_response = other_run.model_responses.create!(test_case: second_case, raw_response: "Manual", status: "completed", tokens_used: 0, cost: BigDecimal("0"))
    other_response.create_review!(reviewer: @owner, status: "passed", notes: "Good")
    other_response.scores.create!(rubric_criterion: empathy, value: 5, feedback: "Strong")

    get project_comparison_dashboard_path(
      project,
      prompt_id: prompt.id,
      run_model: "gpt-4o",
      run_from: 3.days.ago.to_date.iso8601,
      run_to: Date.current.iso8601
    ), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_includes response.body, "Project Analytics"
    assert_includes response.body, "Runs In Scope"
    assert_includes response.body, "Cross-Run Trends"
    assert_includes response.body, "Top Failed Criteria"
    assert_includes response.body, "Weakest Test Cases"
    assert_includes response.body, "Prompt Version Comparison"
    assert_includes response.body, "Scoped Run"
    assert_includes response.body, "Support Prompt"
    assert_not_includes response.body, "Filtered Out Run"
  end

  test "analytics page requires project ownership" do
    project = Project.create!(user: @owner, name: "Private Analytics")

    sign_in_as(@other_user)
    get project_comparison_dashboard_path(project), headers: MODERN_BROWSER_HEADERS

    assert_response :not_found
  end

  test "analytics page asks for prompt selection before comparing versions" do
    sign_in_as(@owner)

    project = Project.create!(user: @owner, name: "Promptless Analytics", description: "Desc")
    prompt = project.prompts.create!(name: "Prompt A", description: "Prompt")
    prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "System",
      user_prompt_template: "Hi {{name}}",
      description: "Version one"
    )

    get project_comparison_dashboard_path(project), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_includes response.body, "Choose a prompt to compare versions"
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
