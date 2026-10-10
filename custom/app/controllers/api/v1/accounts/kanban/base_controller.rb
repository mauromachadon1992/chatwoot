class Api::V1::Accounts::Kanban::BaseController < Api::V1::Accounts::BaseController
  # Which Kanban dialect the compatibility routes speak (custom/contracts/pro-kanban.md).
  DIALECT = 'pro-v1'.freeze

  # Rails would copy a flat JSON body under a key named after the controller (`params[:board]`),
  # and a root key is the Pro dialect's only when the client really sent one.
  wrap_parameters false

  after_action { response.set_header('X-Flow-Kanban-Dialect', DIALECT) }

  private

  def visible_boards
    Custom::Kanban::Board.visible_to(Current.user, Current.account)
  end

  def find_visible_board(id)
    visible_boards.find(id)
  end

  def cards_scope
    Custom::Kanban::Card.includes(:assignee, :tasks, :stage, card_conversations: Custom::Kanban::Card::CONVERSATION_PRELOAD,
                                                             contact: { avatar_attachment: :blob })
  end
end
