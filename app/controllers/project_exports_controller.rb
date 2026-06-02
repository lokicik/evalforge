require "csv"

class ProjectExportsController < ApplicationController
  before_action :set_project

  def test_cases
    csv_data = CSV.generate(headers: true) do |csv|
      csv << [ "Test Case ID", "Input Variables", "Expected Behavior", "Tags", "Difficulty", "Notes", "Created At" ]

      @project.test_cases.order(created_at: :desc).each do |test_case|
        csv << [
          test_case.id,
          test_case.input_variables.to_json,
          test_case.expected_behavior,
          test_case.tags,
          test_case.difficulty,
          test_case.notes,
          test_case.created_at.iso8601
        ]
      end
    end

    send_csv(csv_data, "project-#{@project.id}-test-cases")
  end

  def model_responses
    responses = ModelResponse.joins(evaluation_run: :project)
                             .where(projects: { id: @project.id })
                             .includes(:test_case, :review, evaluation_run: { prompt_version: :prompt })
                             .order(created_at: :desc)

    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        "Model Response ID",
        "Run Name",
        "Prompt",
        "Prompt Version",
        "Model",
        "Test Case ID",
        "Response Status",
        "Model Response",
        "Tokens Used",
        "Cost",
        "Review Status",
        "Average Score %",
        "Reviewer Notes",
        "Created At"
      ]

      responses.each do |response|
        csv << [
          response.id,
          response.evaluation_run.name,
          response.evaluation_run.prompt_version.prompt.name,
          response.evaluation_run.prompt_version.version_number,
          response.evaluation_run.llm_model,
          response.test_case_id,
          response.status,
          response.raw_response,
          response.tokens_used,
          response.cost,
          response.reviewed? ? response.review.status : "pending",
          response.reviewed? ? response.average_score_percentage : nil,
          response.reviewed? ? response.review.notes : nil,
          response.created_at.iso8601
        ]
      end
    end

    send_csv(csv_data, "project-#{@project.id}-model-responses")
  end

  def scores
    scores = Score.joins(model_response: { evaluation_run: :project })
                  .where(projects: { id: @project.id })
                  .includes(:rubric_criterion, model_response: [ :review, :test_case, evaluation_run: { prompt_version: :prompt } ])
                  .order(created_at: :desc)

    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        "Score ID",
        "Run Name",
        "Prompt",
        "Prompt Version",
        "Model",
        "Model Response ID",
        "Test Case ID",
        "Criterion",
        "Criterion Weight",
        "Score",
        "Feedback",
        "Review Status",
        "Created At"
      ]

      scores.each do |score|
        response = score.model_response
        run = response.evaluation_run

        csv << [
          score.id,
          run.name,
          run.prompt_version.prompt.name,
          run.prompt_version.version_number,
          run.llm_model,
          response.id,
          response.test_case_id,
          score.rubric_criterion.name,
          score.rubric_criterion.weight,
          score.value,
          score.feedback,
          response.reviewed? ? response.review.status : "pending",
          score.created_at.iso8601
        ]
      end
    end

    send_csv(csv_data, "project-#{@project.id}-scores")
  end

  def run_summary
    runs = @project.evaluation_runs.includes(:prompt_version)

    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        "Run ID",
        "Run Name",
        "Prompt",
        "Prompt Version",
        "Model",
        "Status",
        "Reviewed Cases",
        "Total Cases",
        "Average Score %",
        "Pass Rate %",
        "Failures",
        "Created At"
      ]

      runs.order(created_at: :desc).each do |run|
        csv << [
          run.id,
          run.name,
          run.prompt_version.prompt.name,
          run.prompt_version.version_number,
          run.llm_model,
          run.status,
          run.reviewed_cases_count,
          run.model_responses.count,
          run.average_score,
          run.pass_rate,
          run.failures_count,
          run.created_at.iso8601
        ]
      end
    end

    send_csv(csv_data, "project-#{@project.id}-run-summary")
  end

  private

  def set_project
    @project = Current.user.projects.find(params[:id])
  end

  def send_csv(csv_data, base_name)
    send_data csv_data,
              filename: "#{base_name}-#{Date.current}.csv",
              type: "text/csv; charset=utf-8; header=present"
  end
end
