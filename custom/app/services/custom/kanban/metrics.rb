# The numbers that say whether a sprint worked (custom/ROADMAP.md → "How we will know it
# worked"), read from the data the Kanban already keeps: counts and rates only, never a name,
# a title or a message.
#
#   Custom::Kanban::Metrics.new(account, since: 30.days.ago).to_h
#   rake 'flow:kanban:metrics[ACCOUNT_ID,DAYS]'
class Custom::Kanban::Metrics
  def initialize(account, since: 30.days.ago, now: Time.current)
    @account = account
    @window = since..now
    @now = now
  end

  def to_h
    { period: { from: @window.begin.iso8601, to: @window.end.iso8601 } }.merge(deals, tasks, notifications)
  end

  private

  def cards
    Custom::Kanban::Card.where(account: @account)
  end

  def deals
    created = cards.where(created_at: @window).group(:source).count
    automatic = cards.where(source: 'automatic', created_at: @window)
    {
      deals: {
        created_manually: created.fetch('manual', 0),
        created_automatically: created.fetch('automatic', 0),
        automatic_share: rate(created.fetch('automatic', 0), created.values.sum),
        automatic_awaiting_review: automatic.where(needs_review: true).count,
        stalled_now: cards.stale(@now).count
      }
    }
  end

  def tasks
    completed = Custom::Kanban::CardTask.where(account: @account, completed_at: @window)
    late = completed.where('flow_kanban_card_tasks.completed_at > flow_kanban_card_tasks.due_at').count
    {
      tasks: {
        created: Custom::Kanban::CardTask.where(account: @account, created_at: @window).count,
        completed: completed.count,
        completed_late: late,
        completed_late_share: rate(late, completed.count),
        overdue_now: Custom::Kanban::CardTask.where(account: @account).overdue.count
      }
    }
  end

  def notifications
    sent = Custom::Kanban::Notification.where(account: @account, created_at: @window)
    by_kind = sent.group(:kind).count
    opened = sent.where.not(read_at: nil).count
    { notifications: { sent: sent.count, opened: opened, opened_share: rate(opened, sent.count), by_kind: by_kind } }
  end

  def rate(part, whole)
    whole.zero? ? nil : (part.to_f / whole).round(3)
  end
end
