class Api::V1::Accounts::Kanban::BaseController < Api::V1::Accounts::BaseController
  private

  def visible_boards
    Custom::Kanban::Board.visible_to(Current.user, Current.account)
  end

  def find_visible_board(id)
    visible_boards.find(id)
  end

  def cards_scope
    Custom::Kanban::Card.includes(:assignee, card_conversations: :conversation, contact: { avatar_attachment: :blob })
  end
end
