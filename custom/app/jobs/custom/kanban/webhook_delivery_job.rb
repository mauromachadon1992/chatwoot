# Sends one delivery and, when the receiver may recover, tries again later: after 1 minute,
# 5 minutes, 30 minutes, then 2 hours, five attempts in all. A delivery already finished, or
# whose webhook was turned off or deleted meanwhile, is left alone.
class Custom::Kanban::WebhookDeliveryJob < ApplicationJob
  queue_as :low

  BACKOFF = [1.minute, 5.minutes, 30.minutes, 2.hours].freeze
  MAX_ATTEMPTS = BACKOFF.size + 1

  def perform(delivery_id)
    delivery = Custom::Kanban::WebhookDelivery.includes(:webhook).find_by(id: delivery_id)
    return unless delivery && %w[pending retrying].include?(delivery.status)

    webhook = delivery.webhook
    return fail_without_sending(delivery, 'webhook_off') unless webhook.active

    record(delivery, Custom::Kanban::WebhookSender.new(webhook, delivery).call)
  end

  private

  def record(delivery, result)
    attempts = delivery.attempts + 1
    attrs = { attempts: attempts, http_status: result.http_status, error: result.error, duration_ms: result.duration_ms }
    if result.success?
      delivery.update!(attrs.merge(status: 'success', delivered_at: Time.current, error: nil))
    elsif result.retryable && attempts < MAX_ATTEMPTS
      delivery.update!(attrs.merge(status: 'retrying'))
      self.class.set(wait: BACKOFF[attempts - 1]).perform_later(delivery.id)
    else
      delivery.update!(attrs.merge(status: 'failed'))
    end
  end

  def fail_without_sending(delivery, reason)
    delivery.update!(status: 'failed', error: reason)
  end
end
