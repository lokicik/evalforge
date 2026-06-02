class AddReportControlsToEvaluationRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :evaluation_runs, :report_expires_at, :datetime
    add_column :evaluation_runs, :report_revoked_at, :datetime
  end
end
