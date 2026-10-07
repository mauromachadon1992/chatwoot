# Kanban sprint 3: what happened to a deal, and what a forecast needs.
#
# - flow_kanban_card_events: the deal's history, append-only (created, moved, value, assignee,
#   tasks, linked conversations, quotes). Backfilled from the stage history that already exists.
# - flow_kanban_lost_reasons: the account's list of why deals are lost.
# - cards: expected_close_on, and why it was lost (a reason and an optional note).
# - stages: win_probability, the chance an open stage's deal is won, for the weighted forecast.
class AddDealHistoryAndForecastFieldsToFlowKanban < ActiveRecord::Migration[7.1]
  def change
    create_card_events
    create_lost_reasons
    add_deal_fields
    reversible { |direction| direction.up { backfill_events } }
  end

  private

  def create_card_events
    create_table :flow_kanban_card_events do |t|
      t.bigint :account_id, null: false
      t.bigint :card_id, null: false
      t.bigint :user_id
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :flow_kanban_card_events, [:card_id, :created_at], name: 'index_flow_kanban_card_events_on_card_and_created'
    add_index :flow_kanban_card_events, [:account_id, :kind, :created_at], name: 'index_flow_kanban_card_events_on_account_kind_created'
    add_foreign_key :flow_kanban_card_events, :accounts, on_delete: :cascade
    add_foreign_key :flow_kanban_card_events, :flow_kanban_cards, column: :card_id, on_delete: :cascade
    add_foreign_key :flow_kanban_card_events, :users, on_delete: :nullify
  end

  def create_lost_reasons
    create_table :flow_kanban_lost_reasons do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :flow_kanban_lost_reasons, 'account_id, lower(name)', unique: true, name: 'index_flow_kanban_lost_reasons_on_account_and_name'
    add_foreign_key :flow_kanban_lost_reasons, :accounts, on_delete: :cascade
  end

  def add_deal_fields
    add_column :flow_kanban_cards, :expected_close_on, :date
    add_column :flow_kanban_cards, :lost_reason_id, :bigint
    add_column :flow_kanban_cards, :lost_note, :text
    add_index :flow_kanban_cards, [:board_id, :expected_close_on], name: 'index_flow_kanban_cards_on_board_and_close'
    add_index :flow_kanban_cards, :lost_reason_id, name: 'index_flow_kanban_cards_on_lost_reason'
    add_foreign_key :flow_kanban_cards, :flow_kanban_lost_reasons, column: :lost_reason_id, on_delete: :nullify

    add_column :flow_kanban_stages, :win_probability, :integer
  end

  # One event per recorded stage entry: the first entry of a deal is its creation.
  def backfill_events
    execute <<~SQL.squish
      INSERT INTO flow_kanban_card_events (account_id, card_id, user_id, kind, data, created_at)
      SELECT t.account_id, t.card_id, t.user_id,
             CASE WHEN t.from_stage_id IS NULL THEN 'created' ELSE 'stage_moved' END,
             jsonb_strip_nulls(jsonb_build_object(
               'from_stage_id', t.from_stage_id, 'to_stage_id', t.to_stage_id,
               'from_stage_name', from_stage.name, 'to_stage_name', to_stage.name)),
             t.created_at
      FROM flow_kanban_stage_transitions t
      LEFT JOIN flow_kanban_stages from_stage ON from_stage.id = t.from_stage_id
      LEFT JOIN flow_kanban_stages to_stage ON to_stage.id = t.to_stage_id
    SQL
  end
end
