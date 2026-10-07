class Custom::Kanban::Stage < ApplicationRecord
  COLOR_FORMAT = /\A#\h{6}\z/

  belongs_to :account
  belongs_to :board, class_name: 'Custom::Kanban::Board', inverse_of: :stages
  has_many :cards, class_name: 'Custom::Kanban::Card', dependent: :restrict_with_error

  # `won` and `lost` close the deal; reports and automations in later phases key off them.
  enum stage_type: { open: 0, won: 1, lost: 2 }, _prefix: true

  # How long a deal may stay before it counts as stalled; open stages only, since a won or lost
  # deal is not waiting for anything.
  STALE_DAYS_RANGE = (1..365)

  validates :name, presence: true, length: { maximum: 80 }
  validates :color, format: { with: COLOR_FORMAT }
  validates :stale_after_days, numericality: { only_integer: true, in: STALE_DAYS_RANGE }, allow_nil: true
  validate :stale_limit_on_open_stage

  before_validation :inherit_account, on: :create
  # Turning a stage into Won or Lost drops its limit rather than refusing the change.
  before_validation :drop_stale_limit, unless: :stage_type_open?
  before_create :append_to_board

  def push_event_data
    { id: id, board_id: board_id, name: name, color: color, stage_type: stage_type, position: position,
      stale_after_days: stale_after_days }
  end

  private

  def drop_stale_limit
    self.stale_after_days = nil
  end

  def stale_limit_on_open_stage
    errors.add(:stale_after_days, :open_only) if stale_after_days && !stage_type_open?
  end

  def inherit_account
    self.account_id ||= board&.account_id
  end

  def append_to_board
    self.position = (board.stages.maximum(:position) || -1) + 1 if position.zero? && board.stages.exists?
  end
end
