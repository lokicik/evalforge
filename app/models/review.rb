class Review < ApplicationRecord
  belongs_to :model_response
  belongs_to :reviewer, class_name: "User"
  has_many :audit_events, class_name: "ReviewAuditEvent", dependent: :destroy

  validates :status, inclusion: { in: %w[passed failed] }
end
