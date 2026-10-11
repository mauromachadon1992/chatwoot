# One attempt series to one webhook for one event: its payload, how many tries, and how it ended.
class Custom::Kanban::WebhookDelivery < ApplicationRecord
  STATUSES = %w[pending retrying success failed].freeze
  RETENTION = 30.days
  LISTED = 50

  belongs_to :webhook, class_name: 'Custom::Kanban::Webhook'

  validates :status, inclusion: { in: STATUSES }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def push_event_data
    { id: id, event: event, card_id: card_id, status: status, attempts: attempts, http_status: http_status,
      error: error, duration_ms: duration_ms, created_at: created_at.to_i, delivered_at: delivered_at&.to_i }
  end
end
