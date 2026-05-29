class EvaluationRun < ApplicationRecord
  belongs_to :project
  belongs_to :prompt_version
  has_many :model_responses, dependent: :destroy
  has_secure_token :share_token

  validates :name, presence: true
  validates :status, inclusion: { in: %w[pending running completed failed] }
  validates :llm_model, inclusion: { in: LlmProviderService.supported_model_keys }
  validate :prompt_version_belongs_to_project

  def to_param
    share_token
  end

  # Calculate average score (weighted if needed, or simple average of averages)
  def average_score
    # Let's collect all scores for all model responses in this run
    all_scores = Score.joins(:model_response).where(model_responses: { evaluation_run_id: id })
    return 0.0 if all_scores.empty?

    # Calculate weighted average or simple average.
    # A standard rubric criterion has a weight.
    # Weighted score = Sum(value * weight) / Sum(weight)
    # Let's do a clean calculation!
    total_points = 0.0
    total_weights = 0.0

    all_scores.includes(:rubric_criterion).each do |score|
      weight = score.rubric_criterion&.weight || 1
      # Normalize 1-5 score to percentage, e.g. (value - 1) / 4.0 * 100 or keep it as 1-5 average.
      # The comparison dashboard shows: Avg Score (e.g. 72%, 84%) or out of 5.
      # Let's normalize it to a percentage (value / 5.0 * 100) or simple average percentage!
      # E.g. (value.to_f / 5.0) * 100
      total_points += (score.value.to_f / 5.0 * 100.0) * weight
      total_weights += weight
    end

    return 0.0 if total_weights == 0
    (total_points / total_weights).round(1)
  end

  # Calculate pass rate
  def pass_rate
    reviewed_responses = model_responses.joins(:review)
    return 0.0 if reviewed_responses.empty?

    passed_count = reviewed_responses.where(reviews: { status: "passed" }).count
    ((passed_count.to_f / reviewed_responses.count) * 100.0).round(1)
  end

  def reviewed_cases_count
    model_responses.joins(:review).count
  end

  def failures_count
    model_responses.joins(:review).where(reviews: { status: "failed" }).count
  end

  private

  def prompt_version_belongs_to_project
    return if project.blank? || prompt_version.blank?
    return if prompt_version.prompt.project_id == project_id

    errors.add(:prompt_version, "must belong to this project")
  end
end
