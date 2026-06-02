require "test_helper"

class ProjectExportsAndAttachmentsTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess::FixtureFile

  setup do
    @user = create_user("exports-owner@example.com")
    @other_user = create_user("exports-other@example.com")
    @project = Project.create!(user: @user, name: "Owner Project", description: "Owned")
    @other_project = Project.create!(user: @other_user, name: "Foreign Project", description: "Foreign")

    prompt = @project.prompts.create!(name: "Prompt")
    prompt_version = prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "System prompt",
      user_prompt_template: "Hello {{name}}",
      description: "Version"
    )
    test_case = @project.test_cases.create!(
      input_variables: { name: "Ada" },
      expected_behavior: "Stay concise",
      tags: "alpha, beta",
      difficulty: "medium",
      notes: "Owner note"
    )
    rubric = @project.rubrics.create!(name: "Rubric", description: "Checks")
    criterion = rubric.rubric_criteria.create!(name: "Accuracy", weight: 3, description: "Stays accurate")

    @run = @project.evaluation_runs.create!(
      name: "Owned Run",
      prompt_version: prompt_version,
      llm_model: "manual",
      status: "completed"
    )
    response = @run.model_responses.create!(
      test_case: test_case,
      raw_response: "Owned raw response",
      status: "completed",
      tokens_used: 120,
      cost: BigDecimal("0.0100")
    )
    response.create_review!(reviewer: @user, status: "passed", notes: "Looks good")
    response.scores.create!(rubric_criterion: criterion, value: 4, feedback: "Strong")

    foreign_prompt = @other_project.prompts.create!(name: "Foreign Prompt")
    foreign_version = foreign_prompt.prompt_versions.create!(
      version_number: 1,
      system_prompt: "Foreign system",
      user_prompt_template: "Foreign {{name}}",
      description: "Foreign version"
    )
    @other_project.test_cases.create!(
      input_variables: { name: "Linus" },
      expected_behavior: "Stay concise",
      tags: "foreign",
      difficulty: "low",
      notes: "Foreign note"
    )
    @other_project.evaluation_runs.create!(
      name: "Foreign Run",
      prompt_version: foreign_version,
      llm_model: "manual",
      status: "completed"
    )
  end

  test "owner can export project test cases csv" do
    sign_in_as(@user)

    get export_test_cases_project_path(@project), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_match(/text\/csv/, response.content_type)
    assert_match(/project-#{@project.id}-test-cases/, response.headers["Content-Disposition"])

    csv = CSV.parse(response.body, headers: true)
    assert_equal [ "Test Case ID", "Input Variables", "Expected Behavior", "Tags", "Difficulty", "Notes", "Created At" ], csv.headers
    assert_equal 1, csv.size
    assert_includes csv.first["Input Variables"], "Ada"
    assert_not_includes response.body, "Foreign note"
  end

  test "owner can export project model responses csv" do
    sign_in_as(@user)

    get export_model_responses_project_path(@project), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_match(/project-#{@project.id}-model-responses/, response.headers["Content-Disposition"])

    csv = CSV.parse(response.body, headers: true)
    assert_includes csv.headers, "Model Response"
    assert_equal "Owned raw response", csv.first["Model Response"]
    assert_equal "passed", csv.first["Review Status"]
  end

  test "owner can export project scores csv" do
    sign_in_as(@user)

    get export_scores_project_path(@project), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_match(/project-#{@project.id}-scores/, response.headers["Content-Disposition"])

    csv = CSV.parse(response.body, headers: true)
    assert_includes csv.headers, "Criterion"
    assert_equal "Accuracy", csv.first["Criterion"]
    assert_equal "4", csv.first["Score"]
  end

  test "owner can export run summary csv" do
    sign_in_as(@user)

    get export_run_summary_project_path(@project), headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_match(/project-#{@project.id}-run-summary/, response.headers["Content-Disposition"])

    csv = CSV.parse(response.body, headers: true)
    assert_equal "Owned Run", csv.first["Run Name"]
    assert_equal @run.average_score.to_s, csv.first["Average Score %"]
    assert_equal @run.pass_rate.to_s, csv.first["Pass Rate %"]
  end

  test "project export endpoints are ownership scoped" do
    sign_in_as(@user)

    get export_test_cases_project_path(@other_project), headers: MODERN_BROWSER_HEADERS

    assert_response :not_found
  end

  test "owner can upload list and delete project reference files" do
    sign_in_as(@user)

    post project_attachments_path(@project), params: {
      project: {
        reference_files: [
          fixture_file_upload("files/reference-note.txt", "text/plain")
        ]
      }
    }, headers: MODERN_BROWSER_HEADERS

    assert_redirected_to project_path(@project)
    @project.reload
    assert_equal 1, @project.reference_files.count
    attachment = @project.reference_files.attachments.first

    get project_path(@project), headers: MODERN_BROWSER_HEADERS
    assert_includes response.body, "reference-note.txt"

    delete project_attachment_path(@project, attachment), headers: MODERN_BROWSER_HEADERS

    assert_redirected_to project_path(@project)
    @project.reload
    assert_equal 0, @project.reference_files.count
  end

  test "project attachments are ownership scoped" do
    sign_in_as(@other_user)

    post project_attachments_path(@project), params: {
      project: {
        reference_files: [
          fixture_file_upload("files/reference-note.txt", "text/plain")
        ]
      }
    }, headers: MODERN_BROWSER_HEADERS

    assert_response :not_found
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
