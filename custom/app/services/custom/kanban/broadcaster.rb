# Realtime fan-out for the Kanban, through the same ActionCable channel the dashboard already
# listens on. Only the board's audience (see Board#member_tokens) receives an event, and the
# payload carries `account_id` because the dashboard drops events of other accounts.
class Custom::Kanban::Broadcaster
  BOARD_UPDATED = 'kanban.board.updated'.freeze
  BOARD_DELETED = 'kanban.board.deleted'.freeze
  CARD_CREATED = 'kanban.card.created'.freeze
  CARD_UPDATED = 'kanban.card.updated'.freeze
  CARD_DELETED = 'kanban.card.deleted'.freeze

  def self.board_updated(board, extra_tokens: [])
    new(board).broadcast(BOARD_UPDATED, { board: board.push_event_data }, extra_tokens: extra_tokens)
  end

  def self.board_deleted(board, tokens)
    new(board).broadcast(BOARD_DELETED, { board: { id: board.id } }, tokens: tokens)
  end

  def self.card_created(card)
    new(card.board).broadcast(CARD_CREATED, { card: card.push_event_data })
  end

  def self.card_updated(card)
    new(card.board).broadcast(CARD_UPDATED, { card: card.push_event_data })
  end

  def self.card_deleted(card)
    new(card.board).broadcast(CARD_DELETED, { card: { id: card.id, board_id: card.board_id, stage_id: card.stage_id } })
  end

  def initialize(board)
    @board = board
  end

  def broadcast(event_name, data, tokens: nil, extra_tokens: [])
    tokens = ((tokens || @board.member_tokens) + extra_tokens).uniq
    return if tokens.blank?

    payload = data.merge(account_id: @board.account_id)
    payload[:performer] = Current.user.push_event_data if Current.user.present?
    ActionCableBroadcastJob.perform_later(tokens, event_name, payload)
  end
end
