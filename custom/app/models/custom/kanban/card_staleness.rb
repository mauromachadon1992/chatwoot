# A deal that stayed in an open stage longer than the stage's limit (stages.stale_after_days),
# counted from when it entered the stage. The stalled-deal job, the "stalled" rules and the
# board filter all read it.
module Custom::Kanban::CardStaleness
  extend ActiveSupport::Concern

  included do
    scope :stale, lambda { |now = Time.current|
      joins(:stage)
        .where(flow_kanban_stages: { stage_type: Custom::Kanban::Stage.stage_types[:open] })
        .where.not(flow_kanban_stages: { stale_after_days: nil })
        .where('COALESCE(flow_kanban_cards.stage_changed_at, flow_kanban_cards.created_at) <= ' \
               'CAST(:now AS timestamp) - make_interval(days => flow_kanban_stages.stale_after_days)', now: now)
    }
  end

  # Whole days in the stage once past its limit, or nil when the deal is not stalled.
  def stale_days(now = Time.current)
    return unless stage&.stage_type_open? && stage.stale_after_days

    days = ((now - (stage_changed_at || created_at)) / 1.day).floor
    days if days >= stage.stale_after_days
  end
end
