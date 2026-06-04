require "test_helper"

class ProjectAnalyticsTest < ActiveSupport::TestCase
  test "returns zeroed summary metrics when no runs are in scope" do
    user = create_user("analytics-empty@example.com")
    project = Project.create!(user: user, name: "Analytics Empty")

    analytics = ProjectAnalytics.new(project: project)

    assert_equal 0, analytics.summary_metrics[:total_runs]
    assert_equal 0, analytics.summary_metrics[:reviewed_responses]
    assert_equal 0.0, analytics.summary_metrics[:average_score]
    assert_equal 0.0, analytics.summary_metrics[:average_pass_rate]
    assert_equal 0, analytics.summary_metrics[:total_tokens_used]
    assert_equal BigDecimal("0.0"), analytics.summary_metrics[:total_cost]
    assert_empty analytics.trend_rows
    assert_empty analytics.criterion_failure_aggregates
    assert_empty analytics.weakest_test_cases
  end

  test "filters analytics by prompt model and date while aggregating failures" do
    user = create_user("analytics-owner@example.com")
    project = Project.create!(user: user, name: "Analytics Project")
    prompt = project.prompts.create!(name: "Primary Prompt")
    version_one = create_version(prompt, 1)
    version_two = create_version(prompt, 2)
    other_prompt = project.prompts.create!(name: "Other Prompt")
    other_version = create_version(other_prompt, 1)
    first_case = project.test_cases.create!(input_variables: { name: "Ada" }, expected_behavior: "Stay helpful", difficulty: "medium", tags: "support")
    second_case = project.test_cases.create!(input_variables: { name: "Linus" }, expected_behavior: "Stay helpful", difficulty: "high", tags: "edge")
    rubric = project.rubrics.create!(name: "Analytics Rubric")
    empathy = rubric.rubric_criteria.create!(name: "Empathy", weight: 3, description: "Empathetic")
    boundaries = rubric.rubric_criteria.create!(name: "Boundaries", weight: 2, description: "Safe")

    in_scope_run = project.evaluation_runs.create!(
      name: "In scope run",
      prompt_version: version_one,
      llm_model: "gpt-4o",
      status: "completed",
      created_at: 2.days.ago
    )
    failed_response = in_scope_run.model_responses.create!(test_case: first_case, raw_response: "failed", status: "completed", tokens_used: 120, cost: BigDecimal("0.0130"))
    failed_response.create_review!(reviewer: user, status: "failed", notes: "Missed tone")
    failed_response.scores.create!(rubric_criterion: empathy, value: 2, feedback: "weak")
    failed_response.scores.create!(rubric_criterion: boundaries, value: 3, feedback: "weak")

    passing_response = in_scope_run.model_responses.create!(test_case: second_case, raw_response: "passed", status: "completed", tokens_used: 90, cost: BigDecimal("0.0090"))
    passing_response.create_review!(reviewer: user, status: "passed", notes: "Good")
    passing_response.scores.create!(rubric_criterion: empathy, value: 5, feedback: "strong")
    passing_response.scores.create!(rubric_criterion: boundaries, value: 4, feedback: "strong")

    out_of_scope_model = project.evaluation_runs.create!(
      name: "Manual run",
      prompt_version: version_two,
      llm_model: "manual",
      status: "completed",
      created_at: 2.days.ago
    )
    manual_response = out_of_scope_model.model_responses.create!(test_case: first_case, raw_response: "manual", status: "completed", tokens_used: 0, cost: BigDecimal("0"))
    manual_response.create_review!(reviewer: user, status: "passed", notes: "Manual")
    manual_response.scores.create!(rubric_criterion: empathy, value: 4, feedback: "fine")

    out_of_scope_prompt = project.evaluation_runs.create!(
      name: "Other prompt run",
      prompt_version: other_version,
      llm_model: "gpt-4o",
      status: "completed",
      created_at: 2.days.ago
    )
    other_response = out_of_scope_prompt.model_responses.create!(test_case: second_case, raw_response: "other", status: "completed", tokens_used: 80, cost: BigDecimal("0.0080"))
    other_response.create_review!(reviewer: user, status: "failed", notes: "Other")
    other_response.scores.create!(rubric_criterion: empathy, value: 1, feedback: "bad")

    out_of_scope_date = project.evaluation_runs.create!(
      name: "Old run",
      prompt_version: version_one,
      llm_model: "gpt-4o",
      status: "completed",
      created_at: 20.days.ago
    )
    old_response = out_of_scope_date.model_responses.create!(test_case: second_case, raw_response: "old", status: "completed", tokens_used: 70, cost: BigDecimal("0.0070"))
    old_response.create_review!(reviewer: user, status: "failed", notes: "Old")
    old_response.scores.create!(rubric_criterion: empathy, value: 1, feedback: "old")

    analytics = ProjectAnalytics.new(
      project: project,
      prompt_id: prompt.id,
      run_model: "gpt-4o",
      run_from: 5.days.ago.to_date,
      run_to: Date.current
    )

    assert_equal 1, analytics.summary_metrics[:total_runs]
    assert_equal 2, analytics.summary_metrics[:reviewed_responses]
    assert_equal 2, analytics.trend_rows.first[:reviewed_cases]
    assert_equal "In scope run", analytics.trend_rows.first[:run].name

    comparison_by_version = analytics.comparison_data.index_by { |entry| entry[:version].id }
    assert_equal 2, comparison_by_version.fetch(version_one.id)[:reviewed_cases]
    assert_equal 0, comparison_by_version.fetch(version_two.id)[:reviewed_cases]

    assert_equal "Empathy", analytics.criterion_failure_aggregates.first[:criterion].name
    assert_equal 1, analytics.criterion_failure_aggregates.first[:failures]

    weakest = analytics.weakest_test_cases.first
    assert_equal first_case, weakest[:test_case]
    assert_equal 100.0, weakest[:failure_rate]
  end

  private

  def create_user(email_address)
    User.create!(
      email_address: email_address,
      password: "password",
      password_confirmation: "password"
    )
  end

  def create_version(prompt, version_number)
    prompt.prompt_versions.create!(
      version_number: version_number,
      system_prompt: "System #{version_number}",
      user_prompt_template: "Hello {{name}} #{version_number}",
      description: "Version #{version_number}"
    )
  end
end
