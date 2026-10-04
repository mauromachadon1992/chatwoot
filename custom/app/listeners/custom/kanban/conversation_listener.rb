# Keeps the conversation chips on Kanban cards current. Conversation events are the same for
# every channel, so this covers WhatsApp, e-mail, the widget and the rest alike.
class Custom::Kanban::ConversationListener < BaseListener
  def conversation_status_changed(event)
    conversation = event.data[:conversation]
    card_ids = Custom::Kanban::CardConversation.where(conversation_id: conversation.id).select(:card_id)

    Custom::Kanban::Card.where(id: card_ids)
                        .includes(:board, :assignee, card_conversations: :conversation, contact: { avatar_attachment: :blob })
                        .find_each { |card| Custom::Kanban::Broadcaster.card_updated(card) }
  end
end
