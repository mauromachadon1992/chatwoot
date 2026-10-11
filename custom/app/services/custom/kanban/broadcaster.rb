# Realtime fan-out for the Kanban, through the same ActionCable channel the dashboard already
# listens on. Only the board's audience (see Board#member_tokens) receives an event, and the
# payload carries `account_id` because the dashboard drops events of other accounts.
class Custom::Kanban::Broadcaster
  BOARD_UPDATED = 'kanban.board.updated'.freeze
  BOARD_DELETED = 'kanban.board.deleted'.freeze
  CARD_CREATED = 'kanban.card.created'.freeze
  CARD_UPDATED = 'kanban.card.updated'.freeze
  CARD_DELETED = 'kanban.card.deleted'.freeze
  TASK_REMINDER = 'kanban.task.reminder'.freeze

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

  # To the assigned agent alone, and only while they still see the board (Board.visible_to):
  # a reminder must not name a card they can no longer open. The text goes out already in the
  # account's language, because the dashboard shows it from anywhere in the app.
  def self.task_reminder(task, now: Time.current)
    board = task.card.board
    return unless Custom::Kanban::Board.visible_to(task.user, board.account).exists?(id: board.id)

    message, open_label = reminder_text(task, board.account, now)
    new(board).broadcast(
      TASK_REMINDER,
      { task: { id: task.id, card_id: task.card_id, board_id: board.id }, message: message, open_label: open_label },
      tokens: [task.user.pubsub_token]
    )
  end

  def self.reminder_text(task, account, now)
    locale = I18n.available_locales.map(&:to_s).include?(account.locale.to_s) ? account.locale : I18n.default_locale
    I18n.with_locale(locale) do
      minutes = [((task.due_at - now) / 60).ceil, 1].max
      key = task.due_at > now ? 'due_soon' : 'overdue'
      [I18n.t("flow_kanban.task_reminder.#{key}", minutes: minutes, title: task.title, card: task.card.title),
       I18n.t('flow_kanban.task_reminder.open')]
    end
  end
  private_class_method :reminder_text

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
