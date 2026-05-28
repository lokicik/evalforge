class EvaluationRunsController < ApplicationController
  before_action :set_project, except: %i[ report ]
  before_action :set_evaluation_run, only: %i[ show destroy report ]

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
      if @evaluation_run.save
        prompt_version = @evaluation_run.prompt_version

        if @evaluation_run.llm_model == "manual"
          tc_ids.each do |tc_id|
            test_case = @project.test_cases.find(tc_id)
            raw_response = generate_mock_response(prompt_version, test_case, "manual")

            @evaluation_run.model_responses.create!(
              test_case: test_case,
              raw_response: raw_response,
              status: "completed",
              tokens_used: 150,
              cost: BigDecimal("0.0000")
            )
          end
          @evaluation_run.update!(status: "completed")
          redirect_to project_evaluation_run_path(@project, @evaluation_run), notice: "Manual evaluation run started and templates generated."
        else
          # Async Job Execution
          @evaluation_run.update!(status: "running")

          tc_ids.each do |tc_id|
            test_case = @project.test_cases.find(tc_id)
            
            model_response = @evaluation_run.model_responses.create!(
              test_case: test_case,
              status: "pending"
            )

            # Queue background job
            EvaluateTestCaseJob.perform_later(model_response.id)
          end

          redirect_to project_evaluation_run_path(@project, @evaluation_run), notice: "Evaluation run launched! Responses are being generated in the background."
        end
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

  # Public report page (read-only)
  def report
    @project = @evaluation_run.project

    # Calculate top failed criteria
    # Group scores by criterion and find average value, sorting for lowest averages!
    all_scores = Score.joins(:model_response).where(model_responses: { evaluation_run_id: @evaluation_run.id })
    @failed_criteria = []
    
    if all_scores.any?
      @failed_criteria = all_scores.group_by(&:rubric_criterion)
                                    .map { |crit, scores| { criterion: crit, avg: (scores.map(&:value).sum.to_f / scores.count).round(2) } }
                                    .select { |c| c[:avg] < 3.5 } # failed threshold
                                    .sort_by { |c| c[:avg] }
    end
  end

  def export_csv
    require "csv"
    @evaluation_run = @project.evaluation_runs.find(params[:id])
    responses = @evaluation_run.model_responses.includes(:test_case, :review, scores: :rubric_criterion)

    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        "Run Name", 
        "Model Name", 
        "Test Case ID", 
        "Variables", 
        "Expected Behavior", 
        "Model Response", 
        "Review Status", 
        "Avg Score %", 
        "Reviewer Notes"
      ]

      responses.each do |resp|
        csv << [
          @evaluation_run.name,
          @evaluation_run.llm_model,
          resp.test_case_id,
          resp.test_case.input_variables.to_json,
          resp.test_case.expected_behavior,
          resp.raw_response,
          resp.reviewed? ? resp.review.status : "pending",
          resp.reviewed? ? "#{resp.average_score_percentage}%" : "N/A",
          resp.reviewed? ? resp.review.notes : ""
        ]
      end
    end

    send_data csv_data, 
              filename: "evaluation-run-#{@evaluation_run.id}-#{Date.today}.csv", 
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
    
    case model_name
    when "manual"
      "[Manual Evaluation Response]\n\n" \
      "Inputs: #{test_case.input_variables.to_json}\n" \
      "Expected standard: #{test_case.expected_behavior}\n\n" \
      "Draft your qualitative response details or use the standard template below:\n" \
      "\"Based on your conversation, I understand you are feeling ignored by your friend. It is completely natural to feel hurt when someone we care about seems distant...\""
    when "gpt-4o"
      "[GPT-4o Simulated Response]\n\n" \
      "I understand how deeply painful it is to feel ignored by a friend. Relationships are core to our emotional well-being, and silence can often feel like rejection. " \
      "Instead of jumping to dramatic conclusions or sending an angry text, I recommend sharing how you feel calmly when you both have space to connect. " \
      "Remember that their silence might be about their own struggles, not your worth."
    when "claude-3-5-sonnet"
      "[Claude-3.5-Sonnet Simulated Response]\n\n" \
      "It is incredibly tough when a friend seems to shut you out or ignore you. Your feelings of hurt and confusion are completely valid. " \
      "Sometimes friends pull back due to personal stress, busyness, or anxiety, rather than active hostility. " \
      "I'd suggest giving them a little breathing room, then reaching out with a simple, low-pressure check-in. Avoid overreacting or jumping to negative assumptions."
    else
      "[Simulated #{model_name} Response]\n\n" \
      "Thank you for reaching out. Based on your prompt configurations and test case variable constraints, here is a comforting and empathetic response designed to validate your emotional experience, without prescribing overly dramatic advice or stepping over personal boundaries."
    end
  end
end
