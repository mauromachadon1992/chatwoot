# Every member reads the catalog, to add products to the deals they work; administrators
# keep it.
class Custom::Kanban::ProductPolicy < ApplicationPolicy
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
