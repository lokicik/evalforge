class Prompt < ApplicationRecord
  belongs_to :project

  has_many :prompt_versions, dependent: :destroy
  has_one :latest_version, -> { order(version_number: :desc) }, class_name: "PromptVersion", dependent: :destroy

  validates :name, presence: true
end
