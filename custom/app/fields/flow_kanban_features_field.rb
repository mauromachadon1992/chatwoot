require 'administrate/field/base'

class FlowKanbanFeaturesField < Administrate::Field::Base
  def options
    Custom::Kanban::Features::ALL
  end

  def selected
    Array(data)
  end

  def to_s
    selected.map { |key| I18n.t("flow_kanban.features.#{key}.label") }.join(', ')
  end
end
