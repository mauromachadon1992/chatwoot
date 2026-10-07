class Custom::Kanban::StageAutomationPolicy < ApplicationPolicy
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

  include Custom::Kanban::HumanAdministrator
end
