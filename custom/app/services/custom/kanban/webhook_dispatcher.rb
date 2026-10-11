# Turns a deal's history line (CardEvent) into deliveries: one for each active webhook of the
# account that listens to the event it maps to. A deal moved onto a won or lost stage is both
# "moved" and "won" or "lost", so a webhook can listen to either. The payload is built here,
# when the change happens, so a late retry or a deleted deal still sends what happened.
class Custom::Kanban::WebhookDispatcher
  def self.call(card_event)
    new(card_event).call
  end

  def initialize(card_event)
    @event = card_event
  end

  def call
    return unless Custom::Kanban::Features.enabled?(@event.card&.account, :webhooks)

    names = event_names
    return if names.empty?

    names.each do |name|
      Custom::Kanban::Webhook.where(account_id: @event.account_id).listening_to(name).find_each do |webhook|
        delivery = webhook.deliveries.create!(card_id: @event.card_id, event: name, payload: payload(name))
        Custom::Kanban::WebhookDeliveryJob.perform_later(delivery.id)
      end
    end
  end

  # What the receiver is sent for a test, as the same shape as a real event.
  def self.payload_for(account, event_name, card: nil, data: {}, occurred_at: Time.current)
    { event: event_name, occurred_at: occurred_at.utc.iso8601, account_id: account.id,
      deal: card && deal_payload(card, account), data: data }
  end

  def self.deal_payload(card, account)
    { id: card.id, title: card.title, board: { id: card.board_id, name: card.board.name },
      stage: { id: card.stage_id, name: card.stage.name, type: card.stage.stage_type },
      value_cents: card.value_cents, currency: account.flow_kanban_currency, expected_close_on: card.expected_close_on,
      contact: card.contact && { id: card.contact_id, name: card.contact.name },
      assignee: card.assignee && { id: card.assignee_id, name: card.assignee.name } }
  end

  private

  def payload(name)
    self.class.payload_for(@event.card.account, name, card: @event.card, data: @event.data, occurred_at: @event.created_at)
  end

  def event_names
    case @event.kind
    when 'created' then ['deal.created']
    when 'value_changed' then ['deal.value_changed']
    when 'task_created' then ['task.created']
    when 'stage_moved' then stage_moved_names
    else []
    end
  end

  def stage_moved_names
    extra = { 'won' => 'deal.won', 'lost' => 'deal.lost' }[@event.data['stage_type']]
    ['deal.moved', extra].compact
  end
end
