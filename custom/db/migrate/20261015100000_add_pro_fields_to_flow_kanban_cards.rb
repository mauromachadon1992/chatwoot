class AddProFieldsToFlowKanbanCards < ActiveRecord::Migration[7.0]
  # The fields the Pro dialect's card has and Flow's had not (custom/contracts/pro-kanban.md):
  # a priority, a start and a due time, free attributes and labels. Labels are the titles an agent
  # or a person typed, kept on the card (the same words the account's labels use).
  def change
    change_table :flow_kanban_cards, bulk: true do |t|
      t.string :priority
      t.datetime :start_at
      t.datetime :due_at
      t.jsonb :custom_attributes, null: false, default: {}
      t.string :labels, array: true, null: false, default: []
    end
    add_index :flow_kanban_cards, :labels, using: :gin, name: 'index_flow_kanban_cards_on_labels'
    add_index :flow_kanban_cards, [:board_id, :priority], name: 'index_flow_kanban_cards_on_board_and_priority'
    add_check_constraint :flow_kanban_cards, "priority IS NULL OR priority IN ('urgent', 'high', 'medium', 'low')",
                         name: 'flow_kanban_cards_priority_known'
    add_check_constraint :flow_kanban_cards, 'start_at IS NULL OR due_at IS NULL OR start_at <= due_at',
                         name: 'flow_kanban_cards_start_before_due'
  end
end
