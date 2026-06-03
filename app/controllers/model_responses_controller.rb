class ModelResponsesController < ApplicationController
  before_action :set_project_and_response

  def claim_review
    if @model_response.reviewed?
      redirect_to project_evaluation_run_path(@project, @model_response.evaluation_run), alert: "This response has already been reviewed."
    elsif @model_response.claimed_by.present? && @model_response.claimed_by != Current.user
      redirect_back fallback_location: review_queue_projects_path, alert: "This response is already claimed by #{@model_response.claimed_by.email_address}."
    else
      @model_response.claim_for!(Current.user)
      redirect_back fallback_location: review_queue_projects_path, notice: "Review claimed."
    end
  end

  def release_review
    if @model_response.claimed_by == Current.user
      @model_response.release_claim!
      redirect_back fallback_location: review_queue_projects_path, notice: "Review claim released."
    else
      redirect_back fallback_location: review_queue_projects_path, alert: "You can only release your own claim."
    end
  end

  private

  def set_project_and_response
    @project = Current.user.projects.find(params[:project_id])
    @model_response = ModelResponse.joins(evaluation_run: :project)
                                   .where(projects: { id: @project.id })
                                   .find(params[:id])
  end
end
