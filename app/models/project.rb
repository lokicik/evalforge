class Project < ApplicationRecord
  belongs_to :user
  has_many_attached :reference_files

  has_many :prompts, dependent: :destroy
  has_many :test_cases, dependent: :destroy
  has_many :rubrics, dependent: :destroy
  has_many :evaluation_runs, dependent: :destroy

  validates :name, presence: true
end
