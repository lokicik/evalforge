class CreateEvalForgeModels < ActiveRecord::Migration[8.0]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.text :description
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    create_table :prompts do |t|
      t.string :name, null: false
      t.text :description
      t.references :project, null: false, foreign_key: true

      t.timestamps
    end

    create_table :prompt_versions do |t|
      t.references :prompt, null: false, foreign_key: true
      t.integer :version_number, null: false, default: 1
      t.text :system_prompt
      t.text :user_prompt_template
      t.text :description

      t.timestamps
    end

    create_table :test_cases do |t|
      t.references :project, null: false, foreign_key: true
      t.jsonb :input_variables, null: false, default: {}
      t.text :expected_behavior
      t.string :tags
      t.string :difficulty, null: false, default: "medium"
      t.text :notes

      t.timestamps
    end

    create_table :rubrics do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    create_table :rubric_criteria do |t|
      t.references :rubric, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :weight, null: false, default: 1
      t.text :description

      t.timestamps
    end

    create_table :evaluation_runs do |t|
      t.references :project, null: false, foreign_key: true
      t.references :prompt_version, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "pending"
      t.string :llm_model, null: false, default: "manual"

      t.timestamps
    end

    create_table :model_responses do |t|
      t.references :evaluation_run, null: false, foreign_key: true
      t.references :test_case, null: false, foreign_key: true
      t.text :raw_response
      t.integer :tokens_used
      t.decimal :cost, precision: 10, scale: 6
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    create_table :scores do |t|
      t.references :model_response, null: false, foreign_key: true
      t.references :rubric_criterion, null: false, foreign_key: { to_table: :rubric_criteria }
      t.integer :value, null: false
      t.text :feedback

      t.timestamps
    end

    create_table :reviews do |t|
      t.references :model_response, null: false, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "passed"
      t.text :notes

      t.timestamps
    end
  end
end
