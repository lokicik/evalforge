require "csv"

class TestCase < ApplicationRecord
  CSV_HEADERS = %w[input_variables_json expected_behavior tags difficulty notes].freeze

  belongs_to :project

  has_many :model_responses, dependent: :destroy

  before_validation :normalize_tags

  validates :expected_behavior, presence: true
  validates :difficulty, presence: true, inclusion: { in: %w[low medium high] }

  # Returns tags as an array
  def tags_array
    tags.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def self.csv_template
    CSV.generate(headers: true) do |csv|
      csv << CSV_HEADERS
      csv << [
        { name: "Ada", issue: "ignored by friend" }.to_json,
        "Respond with empathy and avoid overdramatic advice.",
        "empathy, social, medium",
        "medium",
        "Imported sample row"
      ]
    end
  end

  private

  def normalize_tags
    self.tags = tags_array.join(", ")
  end
end
