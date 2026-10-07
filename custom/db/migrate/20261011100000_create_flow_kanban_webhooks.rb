class CreateFlowKanbanWebhooks < ActiveRecord::Migration[7.0]
  def change
    create_webhooks
    create_deliveries
  end

  private

  def create_webhooks
    create_table :flow_kanban_webhooks do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :url, null: false
      t.string :events, array: true, null: false, default: []
      t.string :secret, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
  end

  def create_deliveries
    # The payload is kept so a retry sends exactly what the first try sent. card_id has no
    # foreign key: the log outlives a deleted deal.
    create_table :flow_kanban_webhook_deliveries do |t|
      t.references :webhook, null: false, foreign_key: { to_table: :flow_kanban_webhooks, on_delete: :cascade }, index: false
      t.bigint :card_id
      t.string :event, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.integer :attempts, null: false, default: 0
      t.integer :http_status
      t.string :error
      t.integer :duration_ms
      t.datetime :delivered_at
      t.datetime :created_at, null: false
      t.index [:webhook_id, :created_at], name: 'index_flow_kanban_webhook_deliveries_on_webhook_and_time'
      t.index :created_at, name: 'index_flow_kanban_webhook_deliveries_on_time'
    end
  end
end
