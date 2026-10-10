# Kanban phase 3: a board's rules that move a card to a stage when its conversation changes.
class CreateFlowKanbanStageAutomations < ActiveRecord::Migration[7.1]
  def change
    create_table :flow_kanban_stage_automations do |t|
      t.bigint :account_id, null: false
      t.bigint :board_id, null: false
      t.bigint :stage_id, null: false
      t.string :trigger_type, null: false
      t.jsonb :trigger_config, null: false, default: {}
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :flow_kanban_stage_automations, [:board_id, :trigger_type], name: 'index_flow_kanban_automations_on_board_and_trigger'
    add_index :flow_kanban_stage_automations, :account_id, name: 'index_flow_kanban_automations_on_account'
    add_index :flow_kanban_stage_automations, :stage_id, name: 'index_flow_kanban_automations_on_stage'

    add_foreign_key :flow_kanban_stage_automations, :accounts, on_delete: :cascade
    add_foreign_key :flow_kanban_stage_automations, :flow_kanban_boards, column: :board_id, on_delete: :cascade
    add_foreign_key :flow_kanban_stage_automations, :flow_kanban_stages, column: :stage_id, on_delete: :cascade
  end
end
