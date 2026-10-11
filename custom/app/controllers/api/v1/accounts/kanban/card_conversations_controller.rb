# Links and unlinks conversations of any inbox to a card. The agent must be able to see both
# the card's board and the conversation itself.
class Api::V1::Accounts::Kanban::CardConversationsController < Api::V1::Accounts::Kanban::BaseController
  before_action :card
  before_action :conversation

  def create
    @card.card_conversations.find_or_create_by!(conversation: @conversation)
    broadcast_updated
  end

  def destroy
    @card.card_conversations.where(conversation: @conversation).delete_all
    broadcast_updated
  end

  private

  def card
    @card = Custom::Kanban::Card.where(board_id: visible_boards.select(:id)).find(params[:card_id])
    authorize @card, :update?
  end

  # `id` on destroy and `conversation_id` on create are both the conversation's display id.
  def conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id] || params[:id])
    authorize @conversation, :show?
  end

  def broadcast_updated
    card = cards_scope.find(@card.id)
    Custom::Kanban::Broadcaster.card_updated(card)
    render json: { payload: card.push_event_data }
  end
end
