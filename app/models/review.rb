class Review < ApplicationRecord
  belongs_to :model_response
  belongs_to :reviewer, class_name: "User"

  validates :status, inclusion: { in: %w[passed failed] }
end
