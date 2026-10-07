class AddDescriptionToFlowKanbanStages < ActiveRecord::Migration[7.0]
  # The Pro dialect's step has a short description (at most 120 characters). Nothing in the
  # dashboard edits it yet; the API takes and returns it.
  def change
    add_column :flow_kanban_stages, :description, :string, limit: 120
  end
end
