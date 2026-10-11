class Custom::Kanban::BoardPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    visible?
  end

  def create?
    administrator?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def visible?
    Custom::Kanban::Board.visible_to(user, account).exists?(id: record.id)
  end
end
