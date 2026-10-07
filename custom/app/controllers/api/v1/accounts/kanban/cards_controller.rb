class Api::V1::Accounts::Kanban::CardsController < Api::V1::Accounts::Kanban::BaseController
  PER_STAGE = 50

  before_action :card, only: [:show, :update, :move, :destroy, :quote]

  # The board view asks for every stage at once (first PER_STAGE cards of each, plus the
  # stage's total); a column's "load more" passes `stage_id` and `offset`. Both honour the
  # same filters, so the totals always describe what the filtered board shows.
  def index
    board = find_visible_board(params[:board_id])
    stages = params[:stage_id].present? ? board.stages.where(id: params[:stage_id]) : board.stages
    offset = params[:offset].to_i
    render json: { payload: stages.map { |stage| column(stage, offset) } }
  end

  # The board's deals, with the filters it is viewed with, as a CSV. Only boards the person sees.
  def export
    board = find_visible_board(params[:board_id])
    cards = filtered(Custom::Kanban::Card.where(board: board)).joins(:stage).reorder('flow_kanban_stages.position, flow_kanban_cards.position')
    send_data Custom::Kanban::CsvExport.deals(cards), type: 'text/csv; charset=utf-8',
                                                      filename: "deals-#{board.name.parameterize.presence || board.id}.csv"
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

  # `reviewed: true` lets an agent accept an automatic deal as it is, without changing anything.
  def update
    @card.assign_attributes(card_params)
    @card.needs_review = false if ActiveModel::Type::Boolean.new.cast(params[:reviewed])
    @card.save!
    broadcast_updated
  end

  # Onto a lost stage the dashboard may send why (`lost_reason_id`, `lost_note`); leaving one
  # forgets it (Card#clear_lost_reason).
  def move
    stage = @card.board.stages.find(params.require(:stage_id))
    @card.move_to!(stage: stage, previous_card_id: params[:previous_card_id], next_card_id: params[:next_card_id],
                   attributes: lost_attributes(stage))
    broadcast_updated
  end

  # The quote an agent took to a conversation, for the deal's history. The message itself is
  # composed in the dashboard and sent by the agent from the conversation.
  def quote
    link = @card.card_conversations.joins(:conversation).find_by!(conversations: { display_id: params.require(:conversation_id) })
    authorize link.conversation, :show?
    Custom::Kanban::CardEvent.record!(@card, 'quote_prepared', { display_id: link.conversation.display_id,
                                                                 total_cents: @card.value_cents, lines: @card.items_count })
    head :ok
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

  def lost_attributes(stage)
    return {} unless stage.stage_type_lost?

    reason = Custom::Kanban::LostReason.where(account: Current.account).find(params[:lost_reason_id]) if params[:lost_reason_id].present?
    { lost_reason: reason, lost_note: params[:lost_note].presence }
  end

  def card_params
    params.permit(:title, :description, :assignee_id, :value_cents, :expected_close_on)
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

  # The "Situation" filter: deals past their stage's limit, or with an overdue follow-up.
  def filtered_by_status(cards)
    case params[:status]
    when 'stale' then cards.stale
    when 'overdue_tasks' then cards.where(id: Custom::Kanban::CardTask.overdue.select(:card_id))
    else cards
    end
  end

  # Deals with a conversation in the inbox.
  def filtered_by_inbox(cards)
    return cards if params[:inbox_id].blank?

    linked = Custom::Kanban::CardConversation.joins(:conversation).where(conversations: { inbox_id: params[:inbox_id] })
    cards.where(id: linked.select(:card_id))
  end

  def filtered(cards)
    cards = filtered_by_inbox(filtered_by_status(cards))
    cards = cards.where(assignee_id: params[:assignee_id] == 'none' ? nil : params[:assignee_id]) if params[:assignee_id].present?
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
