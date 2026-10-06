class Api::V1::Accounts::Kanban::CardsController < Api::V1::Accounts::Kanban::BaseController
  PER_STAGE = 50

  before_action :card, only: [:show, :update, :move, :destroy]

  # The board view asks for every stage at once (first PER_STAGE cards of each, plus the
  # stage's total); a column's "load more" passes `stage_id` and `offset`. Both honour the
  # same filters, so the totals always describe what the filtered board shows.
  def index
    board = find_visible_board(params[:board_id])
    stages = params[:stage_id].present? ? board.stages.where(id: params[:stage_id]) : board.stages
    offset = params[:offset].to_i
    render json: { payload: stages.map { |stage| column(stage, offset) } }
  end

  def show
    render json: { payload: @card.push_event_data(with_items: true) }
  end

  # A card is created on a stage either for a contact or straight from a conversation, in
  # which case the conversation's contact is the card's and the conversation is linked to it.
  def create
    conversation = find_conversation if params[:conversation_id].present?
    card = build_card(conversation&.contact || Current.account.contacts.find(params.require(:contact_id)))
    authorize card

    ActiveRecord::Base.transaction do
      card.save!
      card.card_conversations.create!(conversation: conversation) if conversation
    end
    card = cards_scope.find(card.id)
    Custom::Kanban::Broadcaster.card_created(card)
    render json: { payload: card.push_event_data }
  end

  def update
    @card.update!(card_params)
    broadcast_updated
  end

  def move
    stage = @card.board.stages.find(params.require(:stage_id))
    @card.move_to!(stage: stage, previous_card_id: params[:previous_card_id], next_card_id: params[:next_card_id])
    broadcast_updated
  end

  def destroy
    @card.destroy!
    Custom::Kanban::Broadcaster.card_deleted(@card)
    head :ok
  end

  private

  def card
    @card = cards_scope.where(board_id: visible_boards.select(:id)).find(params[:id])
    authorize @card
  end

  def column(stage, offset)
    cards = filtered(cards_scope.where(stage: stage))
    {
      stage_id: stage.id,
      total: cards.count,
      # Without the preloads: a sum over them would join the conversations and count a card once per link.
      total_value_cents: cards.unscope(:includes).sum(:value_cents),
      cards: cards.ordered.offset(offset).limit(PER_STAGE).map(&:push_event_data)
    }
  end

  def card_params
    params.permit(:title, :description, :assignee_id, :value_cents)
  end

  # The board is set here, not left to validation, because the policy reads it.
  def build_card(contact)
    stage = Custom::Kanban::Stage.where(board_id: visible_boards.select(:id)).find(params.require(:stage_id))
    card = stage.cards.new(card_params.merge(board: stage.board, contact: contact, created_by: Current.user))
    card.title = contact.name.presence || contact.phone_number || contact.email if card.title.blank?
    card
  end

  def find_conversation
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    conversation
  end

  def filtered(cards)
    cards = cards.where(assignee_id: params[:assignee_id] == 'none' ? nil : params[:assignee_id]) if params[:assignee_id].present?
    if params[:inbox_id].present?
      linked = Custom::Kanban::CardConversation.joins(:conversation).where(conversations: { inbox_id: params[:inbox_id] })
      cards = cards.where(id: linked.select(:card_id))
    end
    return cards if params[:q].blank?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
    cards.joins(:contact).where(
      'flow_kanban_cards.title ILIKE :term OR contacts.name ILIKE :term OR contacts.phone_number ILIKE :term OR contacts.email ILIKE :term',
      term: term
    )
  end

  def broadcast_updated
    @card = cards_scope.find(@card.id)
    Custom::Kanban::Broadcaster.card_updated(@card)
    render json: { payload: @card.push_event_data(with_items: true) }
  end
end
