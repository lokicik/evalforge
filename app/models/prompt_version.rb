class PromptVersion < ApplicationRecord
  belongs_to :prompt

  has_many :evaluation_runs, dependent: :nullify

  validates :version_number, presence: true, uniqueness: { scope: :prompt_id }
  validates :system_prompt, presence: true
  validates :user_prompt_template, presence: true

  def interpolate(variables = {})
    return "" if user_prompt_template.blank?
    user_prompt_template.gsub(/\{\{\s*(\w+)\s*\}\}/) do |match|
      key = $1
      # Look up key as string or symbol, fall back to matching string if not found
      variables[key].to_s.presence || variables[key.to_sym].to_s.presence || match
    end
  end
end
