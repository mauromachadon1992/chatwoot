class Custom::Kanban::BoardInbox < ApplicationRecord
  belongs_to :board, class_name: 'Custom::Kanban::Board'
  belongs_to :inbox
end
