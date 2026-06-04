require "test_helper"

class ProjectOnboardingTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email_address: "onboarding@example.com",
      password: "password",
      password_confirmation: "password"
    )
  end

  test "project show displays the setup checklist for incomplete workspaces" do
    sign_in_as(@user)

    project = Project.create!(user: @user, name: "Fresh Project", description: "Needs setup")

    get project_path(project), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_includes response.body, "Project Setup Checklist"
    assert_includes response.body, "Create at least one prompt version"
    assert_includes response.body, "Add a reusable benchmark dataset"
    assert_includes response.body, "Define a scoring rubric"
    assert_includes response.body, "Launch and review an evaluation run"
  end

  test "project show hides the setup checklist after the core workflow exists" do
    sign_in_as(@user)

    project = Project.create!(user: @user, name: "Ready Project", description: "Complete")
    prompt = project.prompts.create!(name: "Prompt", description: "Prompt")
    prompt_version = prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "System prompt",
      user_prompt_template: "Hello {{name}}",
      description: "Version"
    )
    project.test_cases.create!(input_variables: { name: "Ada" }, expected_behavior: "Stay concise", difficulty: "medium")
    rubric = project.rubrics.create!(name: "Rubric", description: "Checks")
    rubric.rubric_criteria.create!(name: "Accuracy", weight: 3, description: "Accurate")
    project.evaluation_runs.create!(name: "Run", prompt_version: prompt_version, llm_model: "manual", status: "completed")

    get project_path(project), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_not_includes response.body, "Project Setup Checklist"
  end
end
