# Importing writes to the whole catalog or a board, so it is for administrators.
class Custom::Kanban::ImportPolicy < ApplicationPolicy
  def create?
    administrator?
  end

  def show?
    administrator?
  end

  def update?
    administrator?
  end

  def run?
    administrator?
  end

  def errors?
    administrator?
  end

  include Custom::Kanban::HumanAdministrator
end
