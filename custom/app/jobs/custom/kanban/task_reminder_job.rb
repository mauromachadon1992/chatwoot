# Announces the tasks about to fall due to the agent they are assigned to. Runs every minute
# (see FlowCustom::Engine); the announcement is a realtime event the dashboard shows as a toast,
# so it reaches only an agent who has the dashboard open. The overdue badge on the card is what
# an agent who was away finds.
class Custom::Kanban::TaskReminderJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    now = Time.current
    Custom::Kanban::CardTask.due_for_reminder(now).includes(:user, card: :board).find_each do |task|
      # The update is the claim: with several workers only the one that flips it announces.
      claimed = Custom::Kanban::CardTask.where(id: task.id, reminded_at: nil).update_all(reminded_at: now) # rubocop:disable Rails/SkipsModelValidations
      next unless claimed == 1

      # The toast reaches an open dashboard; the notification is what an agent who was away finds.
      Custom::Kanban::Broadcaster.task_reminder(task, now: now)
      Custom::Kanban::Notifier.task_reminder(task, now: now)
    end
  end
end
