# The conversation as webhooks and agent bots receive it also carries its deal (`kanban_task`, the Pro
# dialect's shape), so the fazer.ai agents read the card's attributes from the event itself.
# Only `webhook_data`: `push_data` (the cable, agents' dashboards) and `contact_push_data` (the widget)
# stay as they are, so the deal never reaches a contact or someone who cannot see its board.
module Custom::Conversations::EventDataPresenter
  def webhook_data
    super.merge(kanban_task: Custom::Kanban::ProSerializer.card_for_webhook(__getobj__))
  end
end
