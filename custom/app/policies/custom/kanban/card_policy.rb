class Custom::Kanban::CardPolicy < ApplicationPolicy
  # Whoever sees the board works its cards, the way a conversation is worked by whoever
  # sees it. Deleting is narrower: the card holds the deal's history.
  def show?
    board_visible?
  end

  def create?
    board_visible?
  end

  def update?
    board_visible?
  end

  def move?
    board_visible?
  end

  def quote?
    board_visible?
  end

  def destroy?
    return false unless board_visible?

    account_user&.administrator? || record.created_by_id == user.id
  end

  private

  def board_visible?
    Custom::Kanban::Board.visible_to(user, account).exists?(id: record.board_id)
  end
end
