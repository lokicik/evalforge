class AddModelConfigurationToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :default_llm_model, :string, null: false, default: "manual"
    add_column :projects, :allowed_llm_models, :jsonb, null: false, default: []
  end
end
