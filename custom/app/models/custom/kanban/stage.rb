class Custom::Kanban::Stage < ApplicationRecord
  COLOR_FORMAT = /\A#\h{6}\z/

  belongs_to :account
  belongs_to :board, class_name: 'Custom::Kanban::Board', inverse_of: :stages
  has_many :cards, class_name: 'Custom::Kanban::Card', dependent: :restrict_with_error

  # `won` and `lost` close the deal; reports and automations in later phases key off them.
  enum stage_type: { open: 0, won: 1, lost: 2 }, _prefix: true

  validates :name, presence: true, length: { maximum: 80 }
  validates :color, format: { with: COLOR_FORMAT }

  before_validation :inherit_account, on: :create
  before_create :append_to_board

  def push_event_data
    { id: id, board_id: board_id, name: name, color: color, stage_type: stage_type, position: position }
  end

  private

  def inherit_account
    self.account_id ||= board&.account_id
  end

  def append_to_board
    self.position = (board.stages.maximum(:position) || -1) + 1 if position.zero? && board.stages.exists?
  end
end
