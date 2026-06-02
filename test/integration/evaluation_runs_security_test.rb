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

  test "public report shows sanitized sample failures without exposing private content" do
    project = Project.create!(user: @user, name: "Shared Project")
    prompt = project.prompts.create!(name: "Shared Prompt")
    prompt_version = prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "Top secret system prompt",
      user_prompt_template: "Secret template {{name}}",
      description: "Private prompt version"
    )
    failed_rubric = project.rubrics.create!(name: "Quality Rubric", description: "Checks quality")
    empathy = failed_rubric.rubric_criteria.create!(name: "Empathy", weight: 5, description: "Understands feelings")
    boundaries = failed_rubric.rubric_criteria.create!(name: "Boundaries", weight: 4, description: "Avoids overstepping")
    low_case = project.test_cases.create!(
      input_variables: { name: "Ada", issue: "ignored" },
      expected_behavior: "Stay calm",
      tags: "empathy, social",
      difficulty: "high",
      notes: "Private case notes"
    )
    higher_case = project.test_cases.create!(
      input_variables: { name: "Linus", issue: "support" },
      expected_behavior: "Stay calm",
      tags: "support",
      difficulty: "medium",
      notes: "More private notes"
    )
    run = project.evaluation_runs.create!(
      name: "Shared Run",
      prompt_version: prompt_version,
      llm_model: "gpt-4o",
      status: "completed"
    )

    low_response = run.model_responses.create!(
      test_case: low_case,
      raw_response: "Highly sensitive raw output",
      status: "completed"
    )
    low_response.create_review!(reviewer: @user, status: "failed", notes: "Private review notes")
    low_response.scores.create!(rubric_criterion: empathy, value: 1, feedback: "Missed the emotion")
    low_response.scores.create!(rubric_criterion: boundaries, value: 2, feedback: "Too forceful")

    higher_response = run.model_responses.create!(
      test_case: higher_case,
      raw_response: "Another private output",
      status: "completed"
    )
    higher_response.create_review!(reviewer: @user, status: "failed", notes: "Still private")
    higher_response.scores.create!(rubric_criterion: empathy, value: 3, feedback: "Okay")
    higher_response.scores.create!(rubric_criterion: boundaries, value: 4, feedback: "Fine")

    pending_case = project.test_cases.create!(
      input_variables: { name: "Grace" },
      expected_behavior: "Stay calm",
      tags: "pending",
      difficulty: "low"
    )

    run.model_responses.create!(
      test_case: pending_case,
      raw_response: "Pending response should stay hidden",
      status: "completed"
    )

    get public_evaluation_run_report_path(run), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_includes response.body, "Sample Failures"
    assert_includes response.body, "Case ##{low_case.id}"
    assert_includes response.body, "Case ##{higher_case.id}"
    assert_includes response.body, "Empathy"
    assert_includes response.body, "Boundaries"
    assert_includes response.body, "social"
    assert_not_includes response.body, "Top secret system prompt"
    assert_not_includes response.body, "Secret template"
    assert_not_includes response.body, "Highly sensitive raw output"
    assert_not_includes response.body, "Another private output"
    assert_not_includes response.body, "Private review notes"
    assert_not_includes response.body, "\"issue\":\"ignored\""
    assert_operator response.body.index("Case ##{low_case.id}"), :<, response.body.index("Case ##{higher_case.id}")
    assert_not_includes response.body, "Case ##{pending_case.id}"
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
