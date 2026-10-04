class Custom::Kanban::BoardTeam < ApplicationRecord
  belongs_to :board, class_name: 'Custom::Kanban::Board'
  belongs_to :team
end
