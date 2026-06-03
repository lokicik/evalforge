require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "normalizes model configuration and keeps the default inside the allowlist" do
    project = build_project(
      allowed_llm_models: [ "gpt-4o", "gpt-4o", "unsupported-model" ],
      default_llm_model: "claude-3-5-sonnet"
    )

    assert project.valid?
    assert_equal [ "gpt-4o" ], project.allowed_llm_models
    assert_equal "gpt-4o", project.default_llm_model
  end

  test "falls back to the full supported model list when no allowlist is provided" do
    project = build_project(allowed_llm_models: [], default_llm_model: nil)

    assert project.valid?
    assert_equal LlmProviderService.supported_model_keys, project.allowed_llm_models
    assert_equal "manual", project.default_llm_model
  end

  private

  def build_project(attributes = {})
    user = User.create!(
      email_address: "project-models-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password"
    )

    Project.new({ user: user, name: "Configured Project", description: "Desc" }.merge(attributes))
  end
end
