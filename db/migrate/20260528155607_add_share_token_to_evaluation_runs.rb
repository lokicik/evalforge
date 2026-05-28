class AddShareTokenToEvaluationRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :evaluation_runs, :share_token, :string
    add_index :evaluation_runs, :share_token, unique: true
  end
end
