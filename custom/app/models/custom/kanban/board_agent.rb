# An agent a board is shared with (see Board.visible_to).
class Custom::Kanban::BoardAgent < ApplicationRecord
  self.table_name = 'flow_kanban_board_agents'

  belongs_to :board, class_name: 'Custom::Kanban::Board'
  belongs_to :user

  validates :user_id, uniqueness: { scope: :board_id }
end
