require "test_helper"

class ProjectModelConfigurationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = create_user("model-owner@example.com")
    clear_enqueued_jobs
  end

  test "owner can configure enabled models and project default" do
    sign_in_as(@user)

    project = Project.create!(user: @user, name: "Configured Project", description: "Desc")

    patch project_path(project), params: {
      project: {
        name: "Configured Project",
        description: "Desc",
        allowed_llm_models: [ "manual", "claude-3-5-sonnet" ],
        default_llm_model: "claude-3-5-sonnet"
      }
    }, headers: MODERN_BROWSER_HEADERS

    assert_redirected_to project_path(project)
    project.reload
    assert_equal [ "manual", "claude-3-5-sonnet" ], project.allowed_llm_models
    assert_equal "claude-3-5-sonnet", project.default_llm_model
  end

  test "run form uses the project default and hides disabled models" do
    sign_in_as(@user)

    project = create_configured_project(allowed_models: %w[manual claude-3-5-sonnet], default_model: "claude-3-5-sonnet")

    get new_project_evaluation_run_path(project), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_includes response.body, "claude-3-5-sonnet"
    assert_not_includes response.body, "gpt-4o"
    assert_match(/option selected="selected" value="claude-3-5-sonnet"|option value="claude-3-5-sonnet" selected="selected"/, response.body)
  end

  test "creating a run with a model disabled for the project is rejected" do
    sign_in_as(@user)

    project = create_configured_project(allowed_models: %w[manual], default_model: "manual")
    prompt_version = project.prompts.first.prompt_versions.first
    test_case = project.test_cases.first

    assert_no_difference("EvaluationRun.count") do
      post project_evaluation_runs_path(project), params: {
        evaluation_run: {
          name: "Blocked Run",
          prompt_version_id: prompt_version.id,
          llm_model: "gpt-4o"
        },
        test_case_ids: [ test_case.id ]
      }, headers: MODERN_BROWSER_HEADERS
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Llm model is not enabled for this project"
  end

  private

  def create_configured_project(allowed_models:, default_model:)
    project = Project.create!(
      user: @user,
      name: "Configurable Project",
      description: "Desc",
      allowed_llm_models: allowed_models,
      default_llm_model: default_model
    )
    prompt = project.prompts.create!(name: "Prompt", description: "Prompt")
    prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "System prompt",
      user_prompt_template: "Hello {{name}}",
      description: "Version"
    )
    project.test_cases.create!(
      input_variables: { name: "Ada" },
      expected_behavior: "Stay concise",
      difficulty: "medium"
    )
    project
  end

  def create_user(email_address)
    User.create!(
      email_address: email_address,
      password: "password",
      password_confirmation: "password"
    )
  end
end
