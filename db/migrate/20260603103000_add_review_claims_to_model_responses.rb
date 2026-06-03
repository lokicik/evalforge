class AddReviewClaimsToModelResponses < ActiveRecord::Migration[8.1]
  def change
    add_reference :model_responses, :claimed_by, foreign_key: { to_table: :users }
    add_column :model_responses, :claimed_at, :datetime
  end
end
