class RubricCriterion < ApplicationRecord
  self.table_name = "rubric_criteria"

  belongs_to :rubric
  has_many :scores, dependent: :destroy

  validates :name, presence: true
  validates :weight, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
end
