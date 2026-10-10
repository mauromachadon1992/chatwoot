# The Pro Kanban dialect's shapes (custom/contracts/pro-kanban.md), written over Flow's own
# models: a "task" is a Card, a "step" is a Stage. Every field the contract requires is always
# present (null, [] or {} when Flow has no value for it), and Flow's own fields ride along: the
# answer is a superset, never a subset. Money leaves as a number in the account's currency
# (`value`) next to the integer cents (`value_cents`); only cents are ever stored or accepted.
module Custom::Kanban::ProSerializer
  module_function

  def step(stage)
    { id: stage.id, name: stage.name, description: stage.description, color: stage.color, cancelled: stage.stage_type_lost?,
      stage_type: stage.stage_type, position: stage.position }
  end

  # `board` embeds the board's name and steps, as the contract's card does. Preload `board: :stages`
  # (and `:stage`, `:card_conversations`) on a list so this asks the database nothing per card.
  def card(card)
    { id: card.id, board_id: card.board_id, board_step_id: card.stage_id, title: card.title, description: card.description,
      priority: card.priority, status: card.stage.stage_type, value: card.value_cents / 100.0, start_date: card.start_at&.iso8601,
      due_date: card.due_at&.iso8601, custom_attributes: card.custom_attributes, labels: card.labels,
      board: board(card.board) }.merge(flow_fields(card))
  end

  def board(board)
    { id: board.id, name: board.name, steps: board.stages.sort_by { |stage| [stage.position, stage.id] }.map { |stage| step(stage) } }
  end

  # What Flow adds to the contract's card: its own words for the same things, and the links.
  def flow_fields(card)
    { stage_id: card.stage_id, value_cents: card.value_cents, contact_id: card.contact_id, assignee_id: card.assignee_id,
      conversation_ids: card.card_conversations.filter_map { |link| link.conversation&.display_id } }
  end

  def preloaded
    Custom::Kanban::Card.includes(:stage, :contact, board: :stages, card_conversations: :conversation)
  end

  # The one card a conversation shows: the most recently updated open one it is linked to; a
  # conversation linked only to won or lost cards, or to none, has no card. Flow's dashboard still
  # lists every linked card. Only cards on boards `user` sees.
  def card_for_conversation(conversation, user)
    return nil unless user.is_a?(User)

    linked = open_card_of(conversation, preloaded.where(board_id: Custom::Kanban::Board.visible_to(user, conversation.account).select(:id)))
    linked && card(linked)
  end

  # The same card for the webhooks (the Agents read it from the conversation they are sent, so they
  # need no second call): no viewer, so every board, as a webhook carries every message of the conversation.
  def card_for_webhook(conversation)
    linked = open_card_of(conversation, preloaded)
    linked && card(linked)
  end

  def open_card_of(conversation, scope)
    scope.where(id: Custom::Kanban::CardConversation.where(conversation_id: conversation.id).select(:card_id))
         .joins(:stage).where(flow_kanban_stages: { stage_type: Custom::Kanban::Stage.stage_types[:open] })
         .order(updated_at: :desc, id: :desc).first
  end
end
