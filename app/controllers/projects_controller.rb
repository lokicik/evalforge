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
    # All model responses belonging to current user's projects that are completed and do not have a review yet!
    @model_responses = ModelResponse.joins(evaluation_run: :project)
                                    .where(projects: { user_id: Current.user.id })
                                    .where(status: "completed")
                                    .left_outer_joins(:review)
                                    .where(reviews: { id: nil })
                                    .includes(:test_case, evaluation_run: { prompt_version: :prompt })
                                    .order(created_at: :asc)
  end

  # Prompt Version Comparison Dashboard
  def comparison_dashboard
    @project = Current.user.projects.find(params[:project_id])
    @prompts = @project.prompts.includes(:prompt_versions).order(created_at: :desc)
    @selected_prompt = params[:prompt_id].present? ? @project.prompts.find(params[:prompt_id]) : @prompts.first

    if @selected_prompt
      @versions = @selected_prompt.prompt_versions.order(version_number: :desc)
      
      @comparison_data = @versions.map do |version|
        total_scores = Score.joins(model_response: :evaluation_run).where(evaluation_runs: { prompt_version_id: version.id })
        avg_score = 0.0
        
        if total_scores.any?
          total_points = 0.0
          total_weights = 0.0
          total_scores.includes(:rubric_criterion).each do |score|
            weight = score.rubric_criterion&.weight || 1
            total_points += (score.value.to_f / 5.0 * 100.0) * weight
            total_weights += weight
          end
          avg_score = (total_points / total_weights).round(1) if total_weights > 0
        end

        responses = ModelResponse.joins(:evaluation_run).where(evaluation_runs: { prompt_version_id: version.id })
        reviewed_count = responses.joins(:review).count
        passed_count = responses.joins(:review).where(reviews: { status: "passed" }).count
        failures_count = responses.joins(:review).where(reviews: { status: "failed" }).count
        
        pass_rate = reviewed_count > 0 ? ((passed_count.to_f / reviewed_count) * 100.0).round(1) : 0.0

        {
          version: version,
          avg_score: avg_score,
          pass_rate: pass_rate,
          reviewed_cases: reviewed_count,
          failures: failures_count
        }
      end
    else
      @versions = []
      @comparison_data = []
    end
  end

  private

  def set_project
    @project = Current.user.projects.with_attached_reference_files.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description)
  end

  def parse_date_param(value)
    return if value.blank?

    Date.iso8601(value)
  rescue ArgumentError
    nil
  end
end
