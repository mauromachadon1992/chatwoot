# Keeps the bell short: a read notification goes after two weeks, any other after two months
# (a deal nobody opened in that long is not news). The same visit drops the automation runs
# (the "already acted on this episode" claims), the webhook delivery log and the finished CSV
# imports older than their retention.
class Custom::Kanban::NotificationCleanupJob < ApplicationJob
  queue_as :scheduled_jobs

  READ_KEPT_FOR = 14.days
  ANY_KEPT_FOR = 60.days

  def perform
    now = Time.current
    Custom::Kanban::Notification.where.not(read_at: nil).where(read_at: ...(now - READ_KEPT_FOR)).delete_all
    Custom::Kanban::Notification.where(created_at: ...(now - ANY_KEPT_FOR)).delete_all
    Custom::Kanban::AutomationRun.where(created_at: ...(now - Custom::Kanban::AutomationRun::RETENTION)).delete_all
    Custom::Kanban::AiDraft.where(created_at: ...(now - Custom::Kanban::AiDraft::KEPT_FOR)).delete_all
    Custom::Kanban::Import.where(created_at: ...(now - Custom::Kanban::Import::KEPT_FOR)).delete_all
    Custom::Kanban::WebhookDelivery.where(created_at: ...(now - Custom::Kanban::WebhookDelivery::RETENTION)).delete_all
  end
end
