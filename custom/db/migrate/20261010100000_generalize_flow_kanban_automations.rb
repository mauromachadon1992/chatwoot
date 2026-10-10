# Kanban sprint 5: a rule has one trigger and an ordered list of actions (move, create a task,
# assign an agent, add a label), and a deal runs each rule once per trigger episode.
#
# - actions: the list, in jsonb. A rule of sprint 3 becomes a single "move_to_stage" action.
# - stage_id goes away: the stage is now a step of the actions, and a deleted stage must flag the
#   rule ("needs attention"), not delete it through a foreign key.
# - flow_kanban_automation_runs: one row per (rule, deal, episode), unique, so the same event
#   handled twice, or a time-based rule that keeps matching, acts once.
class GeneralizeFlowKanbanAutomations < ActiveRecord::Migration[7.1]
  def up
    add_column :flow_kanban_stage_automations, :actions, :jsonb, null: false, default: []
    execute <<~SQL.squish
      UPDATE flow_kanban_stage_automations
      SET actions = jsonb_build_array(jsonb_build_object('type', 'move_to_stage', 'stage_id', stage_id))
    SQL
    remove_foreign_key :flow_kanban_stage_automations, column: :stage_id
    remove_index :flow_kanban_stage_automations, name: 'index_flow_kanban_automations_on_stage'
    remove_column :flow_kanban_stage_automations, :stage_id

    create_runs_table
  end

  def down
    drop_table :flow_kanban_automation_runs

    add_column :flow_kanban_stage_automations, :stage_id, :bigint
    # A rule without a move has nowhere to put the column back: it goes, as it never existed before.
    execute <<~SQL.squish
      UPDATE flow_kanban_stage_automations a
      SET stage_id = (SELECT (action ->> 'stage_id')::bigint
                      FROM jsonb_array_elements(a.actions) action
                      WHERE action ->> 'type' = 'move_to_stage' LIMIT 1)
    SQL
    execute 'DELETE FROM flow_kanban_stage_automations WHERE stage_id IS NULL OR stage_id NOT IN (SELECT id FROM flow_kanban_stages)'
    change_column_null :flow_kanban_stage_automations, :stage_id, false
    add_index :flow_kanban_stage_automations, :stage_id, name: 'index_flow_kanban_automations_on_stage'
    add_foreign_key :flow_kanban_stage_automations, :flow_kanban_stages, column: :stage_id, on_delete: :cascade
    remove_column :flow_kanban_stage_automations, :actions
  end

  private

  def create_runs_table
    create_table :flow_kanban_automation_runs do |t|
      t.bigint :automation_id, null: false
      t.bigint :card_id, null: false
      t.string :episode_key, null: false
      t.datetime :created_at, null: false
    end
    add_index :flow_kanban_automation_runs, [:automation_id, :card_id, :episode_key], unique: true,
                                                                                      name: 'index_flow_kanban_automation_runs_on_episode'
    add_index :flow_kanban_automation_runs, [:automation_id, :created_at], name: 'index_flow_kanban_automation_runs_on_rule_and_time'
    add_index :flow_kanban_automation_runs, :card_id, name: 'index_flow_kanban_automation_runs_on_card'
    add_foreign_key :flow_kanban_automation_runs, :flow_kanban_stage_automations, column: :automation_id, on_delete: :cascade
    add_foreign_key :flow_kanban_automation_runs, :flow_kanban_cards, column: :card_id, on_delete: :cascade
  end
end
