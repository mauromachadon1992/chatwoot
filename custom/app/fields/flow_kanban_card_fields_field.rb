require 'administrate/field/base'

class FlowKanbanCardFieldsField < Administrate::Field::Base
  def options
    Custom::Kanban::CardFields::ALL
  end

  def selected
    Array(data)
  end

  def to_s
    selected.map { |key| I18n.t("flow_kanban.card_fields.#{key}") }.join(', ')
  end
end
