class CreateFlowKanbanBoardAgents < ActiveRecord::Migration[7.0]
  # Agents a board is shared with, next to its inboxes and teams: a board with any of the three is
  # restricted to the people they name (administrators always see every board).
  def change
    create_table :flow_kanban_board_agents do |t|
      t.references :board, null: false, foreign_key: { to_table: :flow_kanban_boards, on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.timestamps
      t.index [:board_id, :user_id], unique: true, name: 'index_flow_kanban_board_agents_on_board_and_user'
    end
  end
end
