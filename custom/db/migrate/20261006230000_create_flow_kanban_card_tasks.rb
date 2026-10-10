# Kanban phase 3: follow-ups scheduled on a deal (a call, a meeting, an e-mail), each with a
# due date and the agent it is assigned to.
class CreateFlowKanbanCardTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :flow_kanban_card_tasks do |t|
      t.bigint :account_id, null: false
      t.bigint :card_id, null: false
      t.bigint :user_id, null: false
      t.string :title, null: false
      t.text :description
      t.string :task_type, null: false, default: 'call'
      t.datetime :due_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :flow_kanban_card_tasks, [:card_id, :completed_at], name: 'index_flow_kanban_tasks_on_card_and_completed'
    add_index :flow_kanban_card_tasks, [:account_id, :user_id, :due_at], name: 'index_flow_kanban_tasks_on_account_user_due'

    add_foreign_key :flow_kanban_card_tasks, :accounts, on_delete: :cascade
    add_foreign_key :flow_kanban_card_tasks, :flow_kanban_cards, column: :card_id, on_delete: :cascade
    add_foreign_key :flow_kanban_card_tasks, :users, column: :user_id, on_delete: :cascade
  end
end
