require "csv"
require "prawn"

class EvaluationRunsController < ApplicationController
  before_action :set_project, except: %i[ report report_pdf ]
  before_action :set_evaluation_run, only: %i[ show destroy report report_pdf export_csv retry_failed rerun update_report_access regenerate_share_token revoke_share_token ]

  # Skip auth for public report page!
  allow_unauthenticated_access only: %i[ report report_pdf ]

  def show
    @model_responses = @evaluation_run.model_responses.includes(:test_case, :review, scores: :rubric_criterion)
    load_reporting_data
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

  def update_report_access
    expires_at = params.dig(:evaluation_run, :report_expires_at)

    @evaluation_run.update!(
      report_expires_at: expires_at.present? ? Date.iso8601(expires_at).in_time_zone.end_of_day : nil,
      report_revoked_at: nil
    )

    redirect_to project_evaluation_run_path(@project, @evaluation_run), notice: "Public report access updated."
  rescue ArgumentError, TypeError
    redirect_to project_evaluation_run_path(@project, @evaluation_run), alert: "Choose a valid report expiry date."
  end

  def regenerate_share_token
    @evaluation_run.regenerate_public_report!
    redirect_to project_evaluation_run_path(@project, @evaluation_run), notice: "A new public report link has been generated."
  end

  def revoke_share_token
    @evaluation_run.revoke_public_report!
    redirect_to project_evaluation_run_path(@project, @evaluation_run), notice: "The public report link has been revoked."
  end

  # Public report page (read-only)
  def report
    ensure_public_report_available!
    load_reporting_data
  end

  def report_pdf
    ensure_public_report_available!
    load_reporting_data

    pdf = Prawn::Document.new(page_size: "A4", margin: 40)
    pdf.text @evaluation_run.name, size: 24, style: :bold
    pdf.move_down 8
    pdf.text "Prompt: #{@evaluation_run.prompt_version.prompt.name} (V#{@evaluation_run.prompt_version.version_number})"
    pdf.text "Model: #{@evaluation_run.llm_model}"
    pdf.text "Generated: #{Time.current.strftime('%B %d, %Y')}"
    pdf.move_down 16

    pdf.text "Summary", size: 16, style: :bold
    pdf.move_down 8
    pdf.text "Average Score: #{@evaluation_run.average_score}%"
    pdf.text "Pass Rate: #{@evaluation_run.pass_rate}%"
    pdf.text "Reviewed Cases: #{@evaluation_run.reviewed_cases_count} / #{@evaluation_run.model_responses.count}"
    pdf.text "Failures: #{@evaluation_run.failures_count}"
    pdf.text "Pending Review: #{@evaluation_run.pending_review_count}"
    pdf.text "Tokens Used: #{@evaluation_run.total_tokens_used}"
    pdf.text "Run Cost: $#{format('%.6f', @evaluation_run.total_cost)}"
    pdf.move_down 16

    pdf.text "Top Failed Criteria", size: 16, style: :bold
    pdf.move_down 8
    if @failed_criteria.any?
      @failed_criteria.each do |entry|
        pdf.text "#{entry[:criterion].name}: #{entry[:avg]} / 5.0"
      end
    else
      pdf.text "No criteria are below the failure threshold."
    end

    pdf.move_down 16
    pdf.text "Sample Failures", size: 16, style: :bold
    pdf.move_down 8
    if @sample_failures.any?
      @sample_failures.each do |response|
        pdf.text "Case ##{response.test_case_id} | #{response.test_case.difficulty} | #{response.average_score_percentage}%"
        failed_scores = response.scores.select { |score| score.value < 4 }.sort_by(&:value)
        failed_scores.each do |score|
          pdf.text "  - #{score.rubric_criterion.name}: #{score.value} / 5"
        end
        pdf.move_down 6
      end
    else
      pdf.text "No reviewed failed cases are available to sample publicly."
    end

    send_data pdf.render,
              filename: "evaluation-run-#{@evaluation_run.id}-public-report-#{Date.current}.pdf",
              type: "application/pdf",
              disposition: "attachment"
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
    if %w[report report_pdf].include?(action_name)
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

  def ensure_public_report_available!
    raise ActiveRecord::RecordNotFound unless @evaluation_run.public_report_active?
  end

  def load_reporting_data
    @project = @evaluation_run.project
    @failed_criteria = @evaluation_run.failed_criteria_summary
    @sample_failures = @evaluation_run.sample_failures
    @criterion_failure_trends = @evaluation_run.criterion_failure_trends
    @project_model_comparison = @evaluation_run.project_model_comparison
  end
end
