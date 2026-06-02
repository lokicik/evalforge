require "test_helper"

class TestCaseOperationsTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess::FixtureFile

  setup do
    @user = create_user("datasets-owner@example.com")
    @other_user = create_user("datasets-other@example.com")
    @project = Project.create!(user: @user, name: "Dataset Project", description: "Cases")
    @other_project = Project.create!(user: @other_user, name: "Foreign Project", description: "Cases")
  end

  test "owner can download the csv template" do
    sign_in_as(@user)

    get template_project_test_cases_path(@project), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_match(/text\/csv/, response.content_type)
    assert_includes response.body, "input_variables_json"
    assert_includes response.body, "Respond with empathy"
  end

  test "owner can import a csv file with row-level errors" do
    sign_in_as(@user)

    assert_difference("TestCase.count", 1) do
      post import_project_test_cases_path(@project), params: {
        file: fixture_file_upload("files/test-case-import-mixed.csv", "text/csv")
      }, headers: MODERN_BROWSER_HEADERS
    end

    assert_redirected_to project_path(@project, tab: "test_cases")
    follow_redirect!

    imported = @project.test_cases.order(:created_at).last
    assert_equal({ "name" => "Ada", "issue" => "ignored" }, imported.input_variables)
    assert_equal "empathy, social", imported.tags
    assert_includes response.body, "Imported 1 test case"
    assert_includes response.body, "Import Errors"
    assert_includes response.body, "Row 3"
  end

  test "owner can bulk update and bulk delete selected test cases" do
    sign_in_as(@user)

    first_case = @project.test_cases.create!(
      input_variables: { name: "Ada" },
      expected_behavior: "Be concise",
      tags: "baseline",
      difficulty: "low"
    )
    second_case = @project.test_cases.create!(
      input_variables: { name: "Linus" },
      expected_behavior: "Be precise",
      tags: "support",
      difficulty: "medium"
    )

    patch bulk_update_project_test_cases_path(@project), params: {
      test_case_ids: [first_case.id, second_case.id],
      bulk_difficulty: "high",
      bulk_tags: "critical, regression"
    }, headers: MODERN_BROWSER_HEADERS

    assert_redirected_to project_path(@project, tab: "test_cases")
    first_case.reload
    second_case.reload
    assert_equal "high", first_case.difficulty
    assert_equal "high", second_case.difficulty
    assert_includes first_case.tags_array, "critical"
    assert_includes second_case.tags_array, "regression"

    assert_difference("TestCase.count", -1) do
      patch bulk_destroy_project_test_cases_path(@project), params: {
        test_case_ids: [first_case.id]
      }, headers: MODERN_BROWSER_HEADERS
    end

    assert_redirected_to project_path(@project, tab: "test_cases")
    assert_not TestCase.exists?(first_case.id)
    assert TestCase.exists?(second_case.id)
  end

  test "test case filters are scoped to the project" do
    sign_in_as(@user)

    @project.test_cases.create!(
      input_variables: { name: "Ada" },
      expected_behavior: "Comfort the user",
      tags: "empathy, social",
      difficulty: "high",
      notes: "Priority case"
    )
    @project.test_cases.create!(
      input_variables: { name: "Linus" },
      expected_behavior: "Troubleshoot calmly",
      tags: "support",
      difficulty: "low",
      notes: "Routine"
    )
    @other_project.test_cases.create!(
      input_variables: { name: "Foreign" },
      expected_behavior: "Should stay hidden",
      tags: "empathy",
      difficulty: "high"
    )

    get project_path(
      @project,
      tab: "test_cases",
      test_case_query: "Priority",
      test_case_tag: "empathy",
      test_case_difficulty: "high"
    ), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_includes response.body, "Priority case"
    assert_not_includes response.body, "Routine"
    assert_not_includes response.body, "Should stay hidden"
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
