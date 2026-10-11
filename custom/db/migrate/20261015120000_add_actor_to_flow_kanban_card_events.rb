class AddActorToFlowKanbanCardEvents < ActiveRecord::Migration[7.0]
  # Who made a change, as a kind: a person (`user`), a rule (`rule`), the fazer.ai agents' service
  # user (`agent_bot`) or the system. `actor_name` keeps the name as it was then.
  def up
    add_column :flow_kanban_card_events, :actor_kind, :string, null: false, default: 'system'
    add_column :flow_kanban_card_events, :actor_name, :string

    execute <<~SQL.squish
      UPDATE flow_kanban_card_events SET actor_kind = 'user' WHERE user_id IS NOT NULL
    SQL
    execute <<~SQL.squish
      UPDATE flow_kanban_card_events SET actor_kind = 'rule'
      WHERE user_id IS NULL AND (kind = 'automation_ran' OR data ->> 'by_rule' = 'true')
    SQL
    execute <<~SQL.squish
      UPDATE flow_kanban_card_events e SET actor_name = u.name FROM users u WHERE e.user_id = u.id
    SQL
  end

  def down
    remove_column :flow_kanban_card_events, :actor_name
    remove_column :flow_kanban_card_events, :actor_kind
  end
end
