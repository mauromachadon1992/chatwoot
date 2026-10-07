# Kanban phase 3: what happened on a deal that its agent should know, kept until it is read, so an
# agent who was away finds it. The toast of a task reminder only reaches an open dashboard.
class CreateFlowKanbanNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :flow_kanban_notifications do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.bigint :card_id, null: false
      t.bigint :task_id
      t.string :kind, null: false
      # What the text needs, as it was when it happened: a title changed or deleted later does not rewrite the past.
      t.jsonb :data, null: false, default: {}
      t.datetime :read_at

      t.datetime :created_at, null: false
    end

    add_index :flow_kanban_notifications, [:user_id, :read_at, :created_at], name: 'index_flow_kanban_notifications_on_user_read_created'
    add_index :flow_kanban_notifications, :card_id, name: 'index_flow_kanban_notifications_on_card'
    add_index :flow_kanban_notifications, :created_at, name: 'index_flow_kanban_notifications_on_created'

    add_foreign_key :flow_kanban_notifications, :accounts, on_delete: :cascade
    add_foreign_key :flow_kanban_notifications, :users, on_delete: :cascade
    add_foreign_key :flow_kanban_notifications, :flow_kanban_cards, column: :card_id, on_delete: :cascade
    add_foreign_key :flow_kanban_notifications, :flow_kanban_card_tasks, column: :task_id, on_delete: :nullify
  end
end
