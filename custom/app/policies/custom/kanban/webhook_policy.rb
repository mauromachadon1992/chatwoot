# A webhook hears about every board of the account, so only administrators see or change them.
class Custom::Kanban::WebhookPolicy < ApplicationPolicy
  def index?
    administrator?
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

  def test?
    administrator?
  end

  def rotate_secret?
    administrator?
  end

  def deliveries?
    administrator?
  end

  include Custom::Kanban::HumanAdministrator
end
