class ReviewAuditEvent < ApplicationRecord
  belongs_to :review
  belongs_to :actor, class_name: "User"

  validates :action, inclusion: { in: %w[created updated] }
end
