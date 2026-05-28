class ModelResponse < ApplicationRecord
  belongs_to :evaluation_run
  belongs_to :test_case

  has_many :scores, dependent: :destroy
  has_one :review, dependent: :destroy

  validates :status, inclusion: { in: %w[pending completed failed] }

  scope :pending_review_for_user, ->(user) do
    joins(evaluation_run: :project)
      .where(projects: { user_id: user.id }, status: "completed")
      .left_outer_joins(:review)
      .where(reviews: { id: nil })
  end

  def average_score
    return nil if scores.empty?

    total_points = 0.0
    total_weights = 0.0

    scores.includes(:rubric_criterion).each do |score|
      weight = score.rubric_criterion&.weight || 1
      # value is between 1 and 5
      total_points += score.value.to_f * weight
      total_weights += weight
    end

    return 0.0 if total_weights == 0
    (total_points / total_weights).round(2)
  end

  def average_score_percentage
    score = average_score
    return 0.0 unless score
    ((score / 5.0) * 100.0).round(1)
  end

  def reviewed?
    review.present?
  end
end
