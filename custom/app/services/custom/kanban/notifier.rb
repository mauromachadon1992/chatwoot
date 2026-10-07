# Decides who is told what about a deal, and tells them. Four reasons, each one a thing the agent
# can act on, none of them a log of everything that happened:
#
# - a task of theirs is about to fall due, or is overdue (the reminder job);
# - someone else assigned them a task;
# - someone else assigned them a deal;
# - a board rule moved a deal of theirs (nobody was there to tell them).
#
# Never the agent's own doing, and never a deal on a board they cannot see.
class Custom::Kanban::Notifier
  EVENT = 'kanban.notification.created'.freeze

  def self.task_reminder(task, now: Time.current)
    kind = task.due_at > now ? 'task_due' : 'task_overdue'
    notify(kind: kind, user: task.user, card: task.card, task: task, data: { task_title: task.title, due_at: task.due_at.to_i })
  end

  def self.task_assigned(task, actor:)
    notify(kind: 'task_assigned', user: task.user, card: task.card, task: task, actor: actor,
           data: { task_title: task.title, due_at: task.due_at.to_i })
  end

  def self.card_assigned(card, actor:)
    notify(kind: 'card_assigned', user: card.assignee, card: card, actor: actor)
  end

  def self.card_moved(card, stage)
    notify(kind: 'card_moved', user: card.assignee, card: card, data: { stage_name: stage.name, stage_type: stage.stage_type })
  end

  # `details`: the `task` the notification is about, and the `data` its text needs.
  def self.notify(kind:, user:, card:, actor: nil, **details)
    return if user.blank? || user == actor
    return unless Custom::Kanban::Board.visible_to(user, card.account).exists?(id: card.board_id)

    snapshot = details.fetch(:data, {}).merge(card_title: card.title, actor_name: actor&.name).compact
    notification = Custom::Kanban::Notification.create!(account: card.account, user: user, card: card, task: details[:task], kind: kind,
                                                        data: snapshot)
    broadcast(notification)
    notification
  end

  def self.broadcast(notification)
    user = notification.user
    payload = {
      account_id: notification.account_id,
      notification: notification.push_event_data,
      unread_count: Custom::Kanban::Notification.listed_for(user, notification.account).unread.count
    }
    ActionCableBroadcastJob.perform_later([user.pubsub_token], EVENT, payload)
  end
  private_class_method :broadcast
end
