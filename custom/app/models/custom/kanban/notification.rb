# One thing an agent should know about a deal. Written by Custom::Kanban::Notifier, listed in
# the bell of the Kanban, and kept until read (and for a while after).
class Custom::Kanban::Notification < ApplicationRecord
  KINDS = %w[task_due task_overdue task_assigned card_assigned card_moved].freeze
  UNREAD_LIMIT = 99

  belongs_to :account
  belongs_to :user
  belongs_to :card, class_name: 'Custom::Kanban::Card'
  belongs_to :task, class_name: 'Custom::Kanban::CardTask', optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :unread, -> { where(read_at: nil) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # What `user` may read: their own, on cards of boards they still see. Losing a board hides its
  # notifications; getting it back shows them again.
  def self.listed_for(user, account)
    visible_cards = Custom::Kanban::Card.where(board_id: Custom::Kanban::Board.visible_to(user, account).select(:id)).select(:id)
    where(account: account, user: user, card_id: visible_cards)
  end

  def read?
    read_at.present?
  end

  def push_event_data
    { id: id, kind: kind, card_id: card_id, task_id: task_id, data: data, read_at: read_at&.to_i, created_at: created_at.to_i }
  end
end
