# Keeps the conversation chips on Kanban cards current. Conversation events are the same for
# every channel, so this covers WhatsApp, e-mail, the widget and the rest alike.
class Custom::Kanban::ConversationListener < BaseListener
  # A new conversation may open a deal on its own (AutoDealCreator checks every guard).
  def conversation_created(event)
    Custom::Kanban::AutoDealCreator.perform(event.data[:conversation])
  end

  def conversation_status_changed(event)
    conversation = event.data[:conversation]
    card_ids = Custom::Kanban::CardConversation.where(conversation_id: conversation.id).select(:card_id)

    Custom::Kanban::Card.where(id: card_ids)
                        .includes(:board, :assignee, :tasks, :stage, card_conversations: :conversation, contact: { avatar_attachment: :blob })
                        .find_each { |card| Custom::Kanban::Broadcaster.card_updated(card) }
    Custom::Kanban::StageAutomationRunner.status_changed(conversation)
  end

  def conversation_updated(event)
    changes = event.data[:changed_attributes]
    return unless changes.present? && changes.with_indifferent_access.key?(:cached_label_list)

    Custom::Kanban::StageAutomationRunner.labels_changed(event.data[:conversation], changes)
  end
end
