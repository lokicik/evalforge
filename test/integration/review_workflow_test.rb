require "test_helper"

class ReviewWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user("reviewer@example.com")
  end

  test "reviewer can claim and release a pending review from the queue" do
    sign_in_as(@user)

    project, response = build_review_target

    post claim_review_project_model_response_path(project, response), headers: MODERN_BROWSER_HEADERS

    assert_redirected_to review_queue_projects_path
    response.reload
    assert_equal @user, response.claimed_by
    assert response.claimed_at.present?

    post release_review_project_model_response_path(project, response), headers: MODERN_BROWSER_HEADERS

    assert_redirected_to review_queue_projects_path
    response.reload
    assert_nil response.claimed_by
    assert_nil response.claimed_at
  end

  test "starting and updating a review records reviewer attribution and audit history" do
    sign_in_as(@user)

    project, response = build_review_target
    criterion = project.rubrics.first.rubric_criteria.first

    post claim_review_project_model_response_path(project, response), headers: MODERN_BROWSER_HEADERS

    assert_difference("Review.count", 1) do
      assert_difference("ReviewAuditEvent.count", 1) do
        post project_model_response_reviews_path(project, response), params: {
          status: "failed",
          notes: "Needs work",
          scores: { criterion.id.to_s => "2" },
          feedback: { criterion.id.to_s => "Too weak" },
          return_to: review_queue_projects_path
        }, headers: MODERN_BROWSER_HEADERS
      end
    end

    review = response.reload.review
    assert_equal @user, review.reviewer
    assert_equal "created", review.audit_events.last.action
    assert_nil response.claimed_by

    get edit_project_model_response_review_path(project, response, review), headers: MODERN_BROWSER_HEADERS
    assert_response :success
    assert_includes response.body, "Review History"

    assert_difference("ReviewAuditEvent.count", 1) do
      patch project_model_response_review_path(project, response, review), params: {
        status: "passed",
        notes: "Looks good now",
        scores: { criterion.id.to_s => "5" },
        feedback: { criterion.id.to_s => "Improved" }
      }, headers: MODERN_BROWSER_HEADERS
    end

    review.reload
    audit_event = review.audit_events.order(:created_at).last
    assert_equal "updated", audit_event.action
    assert_equal "failed", audit_event.previous_status
    assert_equal "passed", audit_event.new_status
    assert_equal "Needs work", audit_event.previous_notes
    assert_equal "Looks good now", audit_event.new_notes
    assert_equal "passed", review.status
    assert_equal "Looks good now", review.notes
  end

  private

  def build_review_target
    project = Project.create!(user: @user, name: "Review Project", description: "Review workflow")
    prompt = project.prompts.create!(name: "Review Prompt", description: "Prompt")
    prompt_version = prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "System prompt",
      user_prompt_template: "Hello {{name}}",
      description: "Version"
    )
    rubric = project.rubrics.create!(name: "Review Rubric", description: "Checks")
    rubric.rubric_criteria.create!(name: "Accuracy", weight: 3, description: "Accurate")
    test_case = project.test_cases.create!(
      input_variables: { name: "Ada" },
      expected_behavior: "Stay concise",
      difficulty: "medium"
    )
    run = project.evaluation_runs.create!(
      name: "Review Run",
      prompt_version: prompt_version,
      llm_model: "manual",
      status: "completed"
    )
    response = run.model_responses.create!(
      test_case: test_case,
      raw_response: "Generated output",
      status: "completed"
    )

    [ project, response ]
  end

  def create_user(email_address)
    User.create!(
      email_address: email_address,
      password: "password",
      password_confirmation: "password"
    )
  end
end
