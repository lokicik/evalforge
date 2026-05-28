class ReviewsController < ApplicationController
  before_action :set_project_and_response

  def new
    @review = @model_response.build_review
    @criteria = RubricCriterion.joins(rubric: :project).where(projects: { id: @project.id })
  end

  def create
    ActiveRecord::Base.transaction do
      # 1. Create the Review
      @review = @model_response.create_review!(
        reviewer_id: Current.user.id,
        status: params[:status], # "passed" or "failed"
        notes: params[:notes]
      )

      # 2. Save Scores for each Criterion
      scores_param = params[:scores] || {}
      feedback_param = params[:feedback] || {}

      scores_param.each do |crit_id, val|
        next if val.blank?
        @model_response.scores.create!(
          rubric_criterion_id: crit_id,
          value: val.to_i,
          feedback: feedback_param[crit_id]
        )
      end

      # 3. If there is a return_to param, redirect there
      redirect_path = params[:return_to].presence || project_evaluation_run_path(@project, @model_response.evaluation_run)
      redirect_to redirect_path, notice: "Review and scores successfully saved."
    end
  rescue ActiveRecord::RecordInvalid => e
    @criteria = RubricCriterion.joins(rubric: :project).where(projects: { id: @project.id })
    flash.now[:alert] = "Failed to save review: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  private

  def set_project_and_response
    @project = Current.user.projects.find(params[:project_id])
    @model_response = ModelResponse.joins(evaluation_run: :project)
                                   .where(projects: { id: @project.id })
                                   .find(params[:model_response_id])
  end
end
