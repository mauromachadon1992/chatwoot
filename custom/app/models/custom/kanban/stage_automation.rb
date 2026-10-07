# A board rule: when a linked conversation reaches a status or receives a label, the card moves
# to `stage`. The runner applies it (see StageAutomationRunner).
class Custom::Kanban::StageAutomation < ApplicationRecord
  TRIGGER_TYPES = %w[conversation_status_changed label_added].freeze
  LABEL_MAX_LENGTH = 100

  belongs_to :account
  belongs_to :board, class_name: 'Custom::Kanban::Board', inverse_of: :stage_automations
  belongs_to :stage, class_name: 'Custom::Kanban::Stage'

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:id) }

  validates :trigger_type, inclusion: { in: TRIGGER_TYPES }
  validate :trigger_config_matches_trigger
  validate :stage_belongs_to_board

  before_validation :inherit_account, on: :create

  def matches_status?(status)
    trigger_type == 'conversation_status_changed' && trigger_config['status'] == status.to_s
  end

  def matches_label?(label)
    trigger_type == 'label_added' && trigger_config['label'] == label
  end

  def push_event_data
    { id: id, board_id: board_id, stage_id: stage_id, trigger_type: trigger_type, trigger_config: trigger_config, active: active }
  end

  private

  def inherit_account
    self.account_id ||= board&.account_id
  end

  def trigger_config_matches_trigger
    case trigger_type
    when 'conversation_status_changed'
      errors.add(:trigger_config, :invalid) unless Conversation.statuses.key?(trigger_config['status'])
    when 'label_added'
      label = trigger_config['label']
      errors.add(:trigger_config, :invalid) unless label.is_a?(String) && label.present? && label.length <= LABEL_MAX_LENGTH
    end
  end

  def stage_belongs_to_board
    errors.add(:stage, :invalid) if stage && stage.board_id != board_id
  end
end
