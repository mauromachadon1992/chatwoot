# Tells the agent of each deal that stalled past its stage's limit (Stage#stale_after_days),
# once per stall: the claim is `stale_notified_at`, cleared when the deal moves. Runs hourly (see
# FlowCustom::Engine). Accounts whose super admin turned stalled-deal alerts off are skipped and
# their deals left unclaimed, so turning the feature back on still tells about them.
class Custom::Kanban::StaleCardsJob < ApplicationJob
  queue_as :scheduled_jobs

  # What the notification and the board update read, loaded once.
  PRELOADS = [:account, :board, :assignee, :tasks, :stage,
              { card_conversations: :conversation, contact: { avatar_attachment: :blob } }].freeze

  def perform
    now = Time.current
    notify(now)
    run_stalled_rules(now)
  end

  private

  # The alert: one notification per stall, when the account has stalled-deal alerts on.
  def notify(now)
    candidates(now).find_each do |card|
      next unless Custom::Kanban::Features.enabled?(card.account, :stale_alerts)

      claimed = Custom::Kanban::Card.where(id: card.id, stale_notified_at: nil).update_all(stale_notified_at: now) # rubocop:disable Rails/SkipsModelValidations
      next unless claimed == 1

      days = card.stale_days(now)
      Custom::Kanban::Notifier.card_stale(card, days) if days
      Custom::Kanban::Broadcaster.card_updated(card)
    end
  end

  # The rules of boards that have a "stalled" rule, once per stay in the stage (the runner claims it).
  def run_stalled_rules(now)
    board_ids = Custom::Kanban::StageAutomation.active.where(trigger_type: 'deal_stalled').distinct.pluck(:board_id)
    return if board_ids.empty?

    Custom::Kanban::Card.stale(now).where(board_id: board_ids).includes(*PRELOADS).find_each do |card|
      Custom::Kanban::AutomationRunner.deal_stalled(card)
    end
  end

  def candidates(now)
    Custom::Kanban::Card.stale(now).where(stale_notified_at: nil).includes(*PRELOADS)
  end
end
