class TestCase < ApplicationRecord
  belongs_to :project

  has_many :model_responses, dependent: :destroy

  validates :difficulty, presence: true, inclusion: { in: %w[low medium high] }

  # Returns tags as an array
  def tags_array
    tags.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
