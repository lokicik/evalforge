class ReviewsController < ApplicationController
  before_action :set_project_and_response
  before_action :redirect_reviewed_response_to_edit, only: :new
  before_action :set_existing_review, only: %i[ edit update ]
  before_action :ensure_claim_access!, only: %i[ new create edit update ]

  def new
    @model_response.claim_for!(Current.user) unless @model_response.claimed_by == Current.user
    @review = @model_response.build_review
    load_review_form_state
  end

  def create
    ActiveRecord::Base.transaction do
      @review = @model_response.create_review!(
        reviewer_id: Current.user.id,
        status: params[:status],
        notes: params[:notes]
      )

      replace_scores!
      record_audit_event!(@review, action: "created")
      @model_response.release_claim!

      redirect_path = params[:return_to].presence || project_evaluation_run_path(@project, @model_response.evaluation_run)
      redirect_to redirect_path, notice: "Review and scores successfully saved."
    end
  rescue ActiveRecord::RecordInvalid => e
    load_review_form_state
    flash.now[:alert] = "Failed to save review: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  def edit
    load_review_form_state
  end

  def update
    ActiveRecord::Base.transaction do
      previous_status = @review.status
      previous_notes = @review.notes

      @review.update!(
        reviewer_id: Current.user.id,
        status: params[:status],
        notes: params[:notes]
      )

      replace_scores!
      record_audit_event!(
        @review,
        action: "updated",
        previous_status: previous_status,
        previous_notes: previous_notes
      )
      @model_response.release_claim!

      redirect_path = params[:return_to].presence || project_evaluation_run_path(@project, @model_response.evaluation_run)
      redirect_to redirect_path, notice: "Review successfully updated."
    end
  rescue ActiveRecord::RecordInvalid => e
    load_review_form_state
    flash.now[:alert] = "Failed to update review: #{e.message}"
    render :edit, status: :unprocessable_entity
  end

  private

  def set_project_and_response
    @project = Current.user.projects.find(params[:project_id])
    @model_response = ModelResponse.joins(evaluation_run: :project)
                                   .where(projects: { id: @project.id })
                                   .find(params[:model_response_id])
  end

  def set_existing_review
    @review = @model_response.review
  end

  def redirect_reviewed_response_to_edit
    return unless @model_response.reviewed?

    redirect_to edit_project_model_response_review_path(@project, @model_response, @model_response.review, return_to: params[:return_to])
  end

  def ensure_claim_access!
    if @model_response.claimed_by.present? && @model_response.claimed_by != Current.user
      redirect_to review_queue_projects_path, alert: "This response is already claimed by #{@model_response.claimed_by.email_address}."
    end
  end

  def load_review_form_state
    @criteria = RubricCriterion.joins(rubric: :project).where(projects: { id: @project.id })
    @scores_by_criterion = @model_response.scores.index_by(&:rubric_criterion_id)
    @audit_events = @model_response.review&.audit_events&.includes(:actor)&.order(created_at: :desc) || []
  end

  def replace_scores!
    @model_response.scores.destroy_all

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
  end

  def record_audit_event!(review, action:, previous_status: nil, previous_notes: nil)
    review.audit_events.create!(
      actor: Current.user,
      action: action,
      previous_status: previous_status,
      new_status: review.status,
      previous_notes: previous_notes,
      new_notes: review.notes
    )
  end
end
