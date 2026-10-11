class CreateFlowKanbanAiDrafts < ActiveRecord::Migration[7.0]
  def change
    # One request for an AI summary of a deal. The text is not kept: only that it was asked for, by
    # whom, what it used and what the agent did with it. That is enough to limit requests per agent
    # and to read how many drafts were accepted.
    create_table :flow_kanban_ai_drafts do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :card, null: false, foreign_key: { to_table: :flow_kanban_cards, on_delete: :cascade }, index: true
      t.references :user, null: false, foreign_key: true, index: false
      t.string :status, null: false, default: 'pending'
      t.jsonb :used, null: false, default: {}
      t.string :model
      t.datetime :decided_at
      t.datetime :created_at, null: false
      t.index [:user_id, :created_at], name: 'index_flow_kanban_ai_drafts_on_user_and_time'
      t.index [:account_id, :status], name: 'index_flow_kanban_ai_drafts_on_account_and_status'
    end
  end
end
