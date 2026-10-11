# Every member reads the list, to say why a deal was lost; administrators keep it.
class Custom::Kanban::LostReasonPolicy < ApplicationPolicy
  def index?
    true
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
end
