class Score < ApplicationRecord
  belongs_to :model_response
  belongs_to :rubric_criterion

  validates :value, presence: true, inclusion: { in: 1..5 }
end
