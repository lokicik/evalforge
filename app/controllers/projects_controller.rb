class ProjectsController < ApplicationController
  before_action :set_project, only: %i[ show edit update destroy ]

  def index
    @project_query = params[:project_query].to_s.strip
    @projects = Current.user.projects.order(created_at: :desc)

    if @project_query.present?
      @projects = @projects.where("projects.name ILIKE :query OR COALESCE(projects.description, '') ILIKE :query", query: "%#{@project_query}%")
    end
  end

  def show
    @prompt_query = params[:prompt_query].to_s.strip
    @test_case_query = params[:test_case_query].to_s.strip
    @test_case_tag = params[:test_case_tag].to_s.strip
    @test_case_difficulty = params[:test_case_difficulty].to_s.strip
    @run_query = params[:run_query].to_s.strip
    @run_status = params[:run_status].to_s.strip
    @run_model = params[:run_model].to_s.strip
    @run_from = params[:run_from].to_s.strip
    @run_to = params[:run_to].to_s.strip

    @prompts = @project.prompts.includes(:latest_version).order(created_at: :desc)
    if @prompt_query.present?
      @prompts = @prompts.where("prompts.name ILIKE :query OR COALESCE(prompts.description, '') ILIKE :query", query: "%#{@prompt_query}%")
    end

    @test_cases = @project.test_cases.order(created_at: :desc)
    if @test_case_query.present?
      @test_cases = @test_cases.where(
        "expected_behavior ILIKE :query OR COALESCE(notes, '') ILIKE :query OR CAST(input_variables AS TEXT) ILIKE :query OR COALESCE(tags, '') ILIKE :query",
        query: "%#{@test_case_query}%"
      )
    end
    if @test_case_tag.present?
      @test_cases = @test_cases.where("COALESCE(tags, '') ILIKE ?", "%#{@test_case_tag}%")
    end
    @test_cases = @test_cases.where(difficulty: @test_case_difficulty) if @test_case_difficulty.present?
    @rubrics = @project.rubrics.order(created_at: :desc)
    @evaluation_runs = @project.evaluation_runs.includes(prompt_version: :prompt).order(created_at: :desc)

    if @run_query.present?
      @evaluation_runs = @evaluation_runs.joins(prompt_version: :prompt).where(
        "evaluation_runs.name ILIKE :query OR evaluation_runs.llm_model ILIKE :query OR prompts.name ILIKE :query",
        query: "%#{@run_query}%"
      )
    end

    @evaluation_runs = @evaluation_runs.where(status: @run_status) if @run_status.present?
    @evaluation_runs = @evaluation_runs.where(llm_model: @run_model) if @run_model.present?

    run_from_date = parse_date_param(@run_from)
    run_to_date = parse_date_param(@run_to)
    @evaluation_runs = @evaluation_runs.where("evaluation_runs.created_at >= ?", run_from_date.beginning_of_day) if run_from_date
    @evaluation_runs = @evaluation_runs.where("evaluation_runs.created_at <= ?", run_to_date.end_of_day) if run_to_date

    @run_status_options = [ "pending", "running", "completed", "partial", "failed" ]
    @run_model_options = @project.evaluation_runs.distinct.order(:llm_model).pluck(:llm_model)
    @test_case_tag_options = @project.test_cases.flat_map(&:tags_array).uniq.sort
    @test_case_difficulty_options = %w[low medium high]
    @import_errors = Array(flash[:import_errors])
    @import_summary = flash[:import_summary]
    @project_model_warning = LlmProviderService.missing_key_message(@project.default_llm_model_or_fallback) unless ENV["OPENROUTER_API_KEY"].present?
    @onboarding_steps = build_onboarding_steps(@project)
  end

  def new
    @project = Current.user.projects.build
  end

  def edit
  end

  def create
    @project = Current.user.projects.build(project_params)

    if @project.save
      redirect_to @project, notice: "Project was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to projects_url, notice: "Project was successfully destroyed.", status: :see_other
  end

  # Cross-project Human Review Queue
  def review_queue
    @model_responses = ModelResponse.joins(evaluation_run: :project)
                                    .where(projects: { user_id: Current.user.id })
                                    .where(status: "completed")
                                    .left_outer_joins(:review)
                                    .where(reviews: { id: nil })
                                    .includes(:test_case, :claimed_by, evaluation_run: { prompt_version: :prompt })
                                    .order(Arel.sql("CASE WHEN model_responses.claimed_by_id = #{Current.user.id} THEN 0 WHEN model_responses.claimed_by_id IS NULL THEN 1 ELSE 2 END"), claimed_at: :asc, created_at: :asc)
  end

  # Prompt Version Comparison Dashboard
  def comparison_dashboard
    @project = Current.user.projects.find(params[:project_id])
    @run_model = params[:run_model].to_s.strip
    @run_from = parse_date_param(params[:run_from].to_s.strip)
    @run_to = parse_date_param(params[:run_to].to_s.strip)

    @analytics = ProjectAnalytics.new(
      project: @project,
      prompt_id: params[:prompt_id],
      run_model: @run_model,
      run_from: @run_from,
      run_to: @run_to
    )

    @prompts = @analytics.prompts
    @selected_prompt = @analytics.selected_prompt
    @comparison_data = @analytics.comparison_data
    @summary_metrics = @analytics.summary_metrics
    @trend_rows = @analytics.trend_rows
    @criterion_failure_aggregates = @analytics.criterion_failure_aggregates
    @weakest_test_cases = @analytics.weakest_test_cases
    @run_model_options = @analytics.available_models
  end

  private

  def set_project
    @project = Current.user.projects.with_attached_reference_files.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description, :default_llm_model, allowed_llm_models: [])
  end

  def parse_date_param(value)
    return if value.blank?

    Date.iso8601(value)
  rescue ArgumentError
    nil
  end

  def build_onboarding_steps(project)
    [
      {
        title: "Create at least one prompt version",
        complete: project.prompts.joins(:prompt_versions).exists?,
        cta_label: "Add Prompt",
        cta_path: new_project_prompt_path(project),
        detail: "Versioned prompts are the core of each evaluation run."
      },
      {
        title: "Add a reusable benchmark dataset",
        complete: project.test_cases.exists?,
        cta_label: "Add Test Case",
        cta_path: new_project_test_case_path(project),
        detail: "Use tags and difficulty levels so failures are easier to interpret later."
      },
      {
        title: "Define a scoring rubric",
        complete: project.rubrics.joins(:rubric_criteria).exists?,
        cta_label: "Add Rubric",
        cta_path: new_project_rubric_path(project),
        detail: "Weighted criteria turn qualitative reviews into comparable run metrics."
      },
      {
        title: "Launch and review an evaluation run",
        complete: project.evaluation_runs.exists?,
        cta_label: "Start Run",
        cta_path: new_project_evaluation_run_path(project),
        detail: "Runs connect prompt versions, test cases, provider settings, and reviewer workflow."
      }
    ]
  end
end
