class Rubric < ApplicationRecord
  belongs_to :project

  has_many :rubric_criteria, class_name: "RubricCriterion", dependent: :destroy

  validates :name, presence: true
end
