require "csv"

class EvaluationRunsController < ApplicationController
  before_action :set_project, except: %i[ report ]
  before_action :set_evaluation_run, only: %i[ show destroy report export_csv retry_failed rerun ]

  # Skip auth for public report page!
  allow_unauthenticated_access only: %i[ report ]

  def show
    @model_responses = @evaluation_run.model_responses.includes(:test_case, :review, scores: :rubric_criterion)
  end

  def new
    @evaluation_run = @project.evaluation_runs.build
    load_run_form_data
  end

  def create
    @evaluation_run = @project.evaluation_runs.build(evaluation_run_params)
    @evaluation_run.prompt_version = selected_prompt_version
    tc_ids = params[:test_case_ids] || []

    if tc_ids.blank?
      flash.now[:alert] = "You must select at least one test case to run."
      load_run_form_data
      render template: "evaluation_runs/new", status: :unprocessable_entity
      return
    end

    unless @evaluation_run.prompt_version
      @evaluation_run.errors.add(:prompt_version, "must belong to this project")
      load_run_form_data
      render template: "evaluation_runs/new", status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      if launch_evaluation_run!(@evaluation_run, tc_ids)
        notice =
          if @evaluation_run.llm_model == "manual"
            "Manual evaluation run started and templates generated."
          else
            "Evaluation run launched! Responses are being generated in the background."
          end

        redirect_to project_evaluation_run_path(@project, @evaluation_run), notice: notice
      else
        load_run_form_data
        render template: "evaluation_runs/new", status: :unprocessable_entity
      end
    end
  end

  def destroy
    @evaluation_run.destroy
    redirect_to project_path(@project, tab: "evaluation_runs"), notice: "Evaluation run was successfully deleted."
  end

  def retry_failed
    failed_responses = @evaluation_run.retryable_model_responses.includes(:review, :scores)

    if failed_responses.empty?
      redirect_to project_evaluation_run_path(@project, @evaluation_run), notice: "No failed responses were available to retry."
      return
    end

    ActiveRecord::Base.transaction do
      failed_responses.each do |response|
        response.review&.destroy!
        response.scores.destroy_all
        response.update!(
          raw_response: nil,
          tokens_used: nil,
          cost: nil,
          status: "pending"
        )
        EvaluateTestCaseJob.perform_later(response.id)
      end

      @evaluation_run.refresh_status!
    end

    redirect_to project_evaluation_run_path(@project, @evaluation_run), notice: "Retrying #{failed_responses.size} failed response#{'s' unless failed_responses.size == 1}."
  end

  def rerun
    rerun = @project.evaluation_runs.build(
      name: "#{@evaluation_run.name} Rerun #{Time.current.strftime('%Y-%m-%d %H:%M')}",
      prompt_version: @evaluation_run.prompt_version,
      llm_model: @evaluation_run.llm_model
    )

    created = false
    ActiveRecord::Base.transaction do
      created = launch_evaluation_run!(rerun, @evaluation_run.test_case_ids)
      raise ActiveRecord::Rollback unless created
    end

    if created
      redirect_to project_evaluation_run_path(@project, rerun), notice: "Rerun created from #{@evaluation_run.name}."
    else
      redirect_to project_evaluation_run_path(@project, @evaluation_run), alert: "The rerun could not be created."
    end
  rescue ActiveRecord::RecordInvalid
    redirect_to project_evaluation_run_path(@project, @evaluation_run), alert: "The rerun could not be created."
  end

  # Public report page (read-only)
  def report
    @project = @evaluation_run.project

    all_scores = Score.joins(:model_response).where(model_responses: { evaluation_run_id: @evaluation_run.id })
    @failed_criteria = []
    
    if all_scores.any?
      @failed_criteria = all_scores.group_by(&:rubric_criterion)
                                    .map { |crit, scores| { criterion: crit, avg: (scores.map(&:value).sum.to_f / scores.count).round(2) } }
                                    .select { |c| c[:avg] < 3.5 } # failed threshold
                                    .sort_by { |c| c[:avg] }
    end

    @sample_failures = @evaluation_run.model_responses
                                      .includes(:test_case, :review, scores: :rubric_criterion)
                                      .joins(:review)
                                      .where(status: "completed", reviews: { status: "failed" })
                                      .select do |response|
      response.scores.any? { |score| score.value < 4 }
    end
                                      .sort_by { |response| response.average_score || Float::INFINITY }
                                      .first(3)
  end

  def export_csv
    responses = @evaluation_run.model_responses.includes(:test_case, :review, scores: :rubric_criterion)

    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        "Model Response ID",
        "Run Name",
        "Prompt",
        "Prompt Version",
        "Model Name",
        "Test Case ID", 
        "Response Status",
        "Variables", 
        "Expected Behavior", 
        "Model Response", 
        "Tokens Used",
        "Cost",
        "Review Status", 
        "Avg Score %", 
        "Reviewer Notes",
        "Created At"
      ]

      responses.each do |resp|
        csv << [
          resp.id,
          @evaluation_run.name,
          @evaluation_run.prompt_version.prompt.name,
          @evaluation_run.prompt_version.version_number,
          @evaluation_run.llm_model,
          resp.test_case_id,
          resp.status,
          resp.test_case.input_variables.to_json,
          resp.test_case.expected_behavior,
          resp.raw_response,
          resp.tokens_used,
          resp.cost,
          resp.reviewed? ? resp.review.status : "pending",
          resp.reviewed? ? "#{resp.average_score_percentage}%" : "N/A",
          resp.reviewed? ? resp.review.notes : "",
          resp.created_at.iso8601
        ]
      end
    end

    send_data csv_data, 
              filename: "evaluation-run-#{@evaluation_run.id}-model-responses-#{Date.current}.csv", 
              type: "text/csv; charset=utf-8; header=present"
  end

  private

  def set_project
    @project = Current.user.projects.find(params[:project_id])
  end

  def set_evaluation_run
    if action_name == "report"
      @evaluation_run = EvaluationRun.find_by!(share_token: params[:share_token])
    else
      @evaluation_run = @project.evaluation_runs.find(params[:id])
    end
  end

  def evaluation_run_params
    params.require(:evaluation_run).permit(:name, :llm_model)
  end

  def selected_prompt_version
    prompt_version_id = params.dig(:evaluation_run, :prompt_version_id)
    return if prompt_version_id.blank?

    PromptVersion.joins(:prompt)
                 .where(prompts: { project_id: @project.id })
                 .find_by(id: prompt_version_id)
  end

  def load_run_form_data
    @prompt_versions = PromptVersion.joins(prompt: :project).where(projects: { id: @project.id }).order("prompts.name ASC, prompt_versions.version_number DESC")
    @test_cases = @project.test_cases.order(created_at: :desc)
  end

  def generate_mock_response(prompt_version, test_case, model_name)
    user_prompt = prompt_version.interpolate(test_case.input_variables)

    "[Manual Evaluation Response]\n\n" \
    "Inputs: #{test_case.input_variables.to_json}\n" \
    "Expected standard: #{test_case.expected_behavior}\n\n" \
    "Draft your qualitative response details or use the standard template below:\n" \
    "\"Based on your conversation, I understand you are feeling ignored by your friend. It is completely natural to feel hurt when someone we care about seems distant...\"\n\n" \
    "Resolved prompt preview:\n#{user_prompt.first(200)}"
  end

  def launch_evaluation_run!(evaluation_run, tc_ids)
    return false unless evaluation_run.save

    prompt_version = evaluation_run.prompt_version

    if evaluation_run.llm_model == "manual"
      tc_ids.each do |tc_id|
        test_case = @project.test_cases.find(tc_id)
        raw_response = generate_mock_response(prompt_version, test_case, "manual")

        evaluation_run.model_responses.create!(
          test_case: test_case,
          raw_response: raw_response,
          status: "completed",
          tokens_used: 150,
          cost: BigDecimal("0.0000")
        )
      end
    else
      tc_ids.each do |tc_id|
        test_case = @project.test_cases.find(tc_id)

        model_response = evaluation_run.model_responses.create!(
          test_case: test_case,
          status: "pending"
        )

        EvaluateTestCaseJob.perform_later(model_response.id)
      end
    end

    evaluation_run.refresh_status!
    true
  end
end
