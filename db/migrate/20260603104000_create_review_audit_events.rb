class CreateReviewAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :review_audit_events do |t|
      t.references :review, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :previous_status
      t.string :new_status
      t.text :previous_notes
      t.text :new_notes

      t.timestamps
    end
  end
end
