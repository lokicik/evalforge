class EvaluationRun < ApplicationRecord
  belongs_to :project
  belongs_to :prompt_version
  has_many :model_responses, dependent: :destroy
  has_secure_token :share_token

  validates :name, presence: true
  validates :status, inclusion: { in: %w[pending running completed partial failed] }
  validates :llm_model, inclusion: { in: LlmProviderService.supported_model_keys }
  validate :prompt_version_belongs_to_project
  validate :llm_model_allowed_for_project

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

  def pending_review_count
    model_responses.where(status: "completed").left_outer_joins(:review).where(reviews: { id: nil }).count
  end

  def total_tokens_used
    model_responses.sum(:tokens_used)
  end

  def total_cost
    model_responses.sum(:cost).to_d.round(6)
  end

  def failure_rate
    return 0.0 if reviewed_cases_count.zero?

    ((failures_count.to_f / reviewed_cases_count) * 100.0).round(1)
  end

  def report_revoked?
    report_revoked_at.present?
  end

  def report_expired?
    report_expires_at.present? && report_expires_at <= Time.current
  end

  def public_report_active?
    !report_revoked? && !report_expired?
  end

  def regenerate_public_report!
    update!(share_token: SecureRandom.base58(24), report_revoked_at: nil)
  end

  def revoke_public_report!
    update!(report_revoked_at: Time.current)
  end

  def criterion_failure_trends
    scores = Score.joins(model_response: :review)
                  .where(model_responses: { evaluation_run_id: id }, reviews: { status: "failed" })
                  .includes(:rubric_criterion)

    scores.group_by(&:rubric_criterion).map do |criterion, criterion_scores|
      {
        criterion: criterion,
        failures: criterion_scores.count,
        average_score: (criterion_scores.sum(&:value).to_f / criterion_scores.count).round(2)
      }
    end.sort_by { |entry| [ -entry[:failures], entry[:average_score] ] }
  end

  def sample_failures(limit: 3)
    model_responses
      .includes(:test_case, :review, scores: :rubric_criterion)
      .joins(:review)
      .where(status: "completed", reviews: { status: "failed" })
      .select { |response| response.scores.any? { |score| score.value < 4 } }
      .sort_by { |response| response.average_score || Float::INFINITY }
      .first(limit)
  end

  def failed_criteria_summary
    all_scores = Score.joins(:model_response).where(model_responses: { evaluation_run_id: id })
    return [] unless all_scores.any?

    all_scores.group_by(&:rubric_criterion)
              .map { |crit, scores| { criterion: crit, avg: (scores.map(&:value).sum.to_f / scores.count).round(2) } }
              .select { |entry| entry[:avg] < 3.5 }
              .sort_by { |entry| entry[:avg] }
  end

  def project_model_comparison
    project.evaluation_runs
           .joins(:model_responses)
           .where.not(id: nil)
           .group_by(&:llm_model)
           .map do |model_name, runs|
      average_score = runs.sum(&:average_score) / runs.size.to_f
      average_pass_rate = runs.sum(&:pass_rate) / runs.size.to_f
      total_failures = runs.sum(&:failures_count)

      {
        model_name: model_name,
        runs_count: runs.size,
        average_score: average_score.round(1),
        average_pass_rate: average_pass_rate.round(1),
        total_failures: total_failures
      }
    end.sort_by { |entry| -entry[:average_score] }
  end

  def pending_responses_count
    model_responses.where(status: "pending").count
  end

  def completed_responses_count
    model_responses.where(status: "completed").count
  end

  def failed_responses_count
    model_responses.where(status: "failed").count
  end

  def retryable_model_responses
    model_responses.where(status: "failed")
  end

  def test_case_ids
    model_responses.order(:id).pluck(:test_case_id).uniq
  end

  def status_summary
    return "No responses have been generated yet." if model_responses.empty?
    return "Responses are still being generated." if pending_responses_count.positive?
    return "All response jobs failed." if failed_responses_count == model_responses.count
    return "Run completed with partial failures." if failed_responses_count.positive?

    "All response jobs completed successfully."
  end

  def refresh_status!
    next_status =
      if model_responses.empty?
        "pending"
      elsif pending_responses_count.positive?
        "running"
      elsif failed_responses_count == model_responses.count
        "failed"
      elsif failed_responses_count.positive?
        "partial"
      else
        "completed"
      end

    update!(status: next_status) if status != next_status
  end

  private

  def prompt_version_belongs_to_project
    return if project.blank? || prompt_version.blank?
    return if prompt_version.prompt.project_id == project_id

    errors.add(:prompt_version, "must belong to this project")
  end

  def llm_model_allowed_for_project
    return if project.blank? || llm_model.blank?
    return if project.allowed_llm_models.include?(llm_model)

    errors.add(:llm_model, "is not enabled for this project")
  end
end
