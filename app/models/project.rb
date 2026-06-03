class Project < ApplicationRecord
  belongs_to :user
  has_many_attached :reference_files

  has_many :prompts, dependent: :destroy
  has_many :test_cases, dependent: :destroy
  has_many :rubrics, dependent: :destroy
  has_many :evaluation_runs, dependent: :destroy

  validates :name, presence: true
  validates :default_llm_model, inclusion: { in: ->(*) { LlmProviderService.supported_model_keys } }
  validate :allowed_llm_models_are_supported
  validate :default_llm_model_is_allowed

  before_validation :normalize_model_configuration

  def allowed_llm_models
    configured = super
    normalized = Array(configured).presence || LlmProviderService.supported_model_keys
    normalized.map(&:to_s)
  end

  def allowed_llm_options_for_select
    LlmProviderService.options_for_select(allowed_llm_models)
  end

  def default_llm_model_or_fallback
    allowed_llm_models.include?(default_llm_model) ? default_llm_model : allowed_llm_models.first
  end

  def openrouter_models_enabled?
    allowed_llm_models.any? { |model| LlmProviderService.openrouter_required_for?(model) }
  end

  private

  def normalize_model_configuration
    self.allowed_llm_models = Array(allowed_llm_models).map(&:to_s).uniq.select { |model| LlmProviderService.supported_model_keys.include?(model) }
    self.allowed_llm_models = LlmProviderService.supported_model_keys if allowed_llm_models.empty?
    self.default_llm_model = default_llm_model.presence&.to_s || "manual"
    self.default_llm_model = allowed_llm_models.first unless allowed_llm_models.include?(default_llm_model)
  end

  def allowed_llm_models_are_supported
    invalid_models = allowed_llm_models - LlmProviderService.supported_model_keys
    return if invalid_models.empty?

    errors.add(:allowed_llm_models, "contains unsupported models: #{invalid_models.join(', ')}")
  end

  def default_llm_model_is_allowed
    return if allowed_llm_models.include?(default_llm_model)

    errors.add(:default_llm_model, "must be included in the allowed models for this project")
  end
end
