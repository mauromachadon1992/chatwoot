# Feeds the Kanban panel of the conversation sidebar: the cards this conversation is on, and
# the contact's other cards it could be linked to. Only boards the agent can see count.
class Api::V1::Accounts::Kanban::ConversationCardsController < Api::V1::Accounts::Kanban::BaseController
  def index
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?

    cards = cards_scope.includes(:board, :stage).where(board_id: visible_boards.select(:id))
    linked_ids = Custom::Kanban::CardConversation.where(conversation: conversation).select(:card_id)

    render json: {
      payload: {
        linked: cards.where(id: linked_ids).order(:updated_at).map { |card| panel_data(card) },
        contact_cards: cards.where(contact_id: conversation.contact_id).where.not(id: linked_ids).order(:updated_at).map { |card| panel_data(card) }
      }
    }
  end

  private

  def panel_data(card)
    card.push_event_data.merge(
      board: { id: card.board.id, name: card.board.name },
      stage: card.stage.push_event_data
    )
  end
end
