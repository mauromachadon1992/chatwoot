# Writes a deal's history (CardEvent) from what the card saves: its creation, stage moves (with
# the lost reason when it lands on a lost stage), value and assignee changes. Tasks, linked
# conversations and quotes write their own lines where they happen.
module Custom::Kanban::CardHistory
  extend ActiveSupport::Concern

  included do
    has_many :events, class_name: 'Custom::Kanban::CardEvent', dependent: :delete_all

    after_create :record_created_event
    after_update :record_update_events
  end

  private

  def record_created_event
    Custom::Kanban::CardEvent.record!(self, 'created', { stage_id: stage_id, stage_name: stage.name, source: source })
  end

  def record_update_events
    record_stage_move if saved_change_to_stage_id?
    record_value_change if saved_change_to_value_cents?
    record_assignee_change if saved_change_to_assignee_id?
  end

  def record_stage_move
    from_id, to_id = saved_change_to_stage_id
    data = { from_stage_id: from_id, to_stage_id: to_id, from_stage_name: Custom::Kanban::Stage.find_by(id: from_id)&.name,
             to_stage_name: stage.name, stage_type: stage.stage_type, by_rule: Current.user.nil? || nil }
    if stage.stage_type_lost?
      data[:lost_reason] = lost_reason&.name
      data[:lost_note] = lost_note.presence
    end
    Custom::Kanban::CardEvent.record!(self, 'stage_moved', data)
  end

  def record_value_change
    from_cents, to_cents = saved_change_to_value_cents
    Custom::Kanban::CardEvent.record!(self, 'value_changed', { from_cents: from_cents, to_cents: to_cents,
                                                               from_items: items_count.positive? || nil })
  end

  def record_assignee_change
    from_id, = saved_change_to_assignee_id
    Custom::Kanban::CardEvent.record!(self, 'assignee_changed', { from_name: User.find_by(id: from_id)&.name, to_name: assignee&.name })
  end
end
