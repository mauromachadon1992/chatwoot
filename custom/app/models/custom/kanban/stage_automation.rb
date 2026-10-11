# A board rule: one trigger, and an ordered list of actions run on the deal when it fires. The
# name is the one of sprint 3, when a rule could only move a deal to a stage. AutomationRunner
# applies the rules, once per trigger episode (AutomationRun).
class Custom::Kanban::StageAutomation < ApplicationRecord
  TRIGGER_TYPES = %w[conversation_status_changed label_added deal_created deal_stalled no_reply].freeze
  MAX_ACTIONS = 5
  # A safety valve per rule per day: turning on "no reply for 24 h" on a board of old deals must
  # not act on all of them in one go.
  RUNS_PER_DAY = 200

  include Custom::Kanban::AutomationTrigger

  belongs_to :account
  belongs_to :board, class_name: 'Custom::Kanban::Board', inverse_of: :stage_automations
  has_many :runs, class_name: 'Custom::Kanban::AutomationRun', foreign_key: :automation_id, dependent: :delete_all, inverse_of: :automation

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:id) }

  validate :actions_are_valid

  before_validation :inherit_account, on: :create
  before_validation :normalise_actions

  def steps
    Custom::Kanban::AutomationAction.parse(actions)
  end

  # What the rule points at that no longer exists (a deleted stage, agent or label). Such a rule
  # is shown with the reasons and never run: half a rule is worse than none.
  def needs_attention
    steps.flat_map { |step| step.missing(self) }.uniq
  end

  def runnable?
    active && needs_attention.empty?
  end

  def runs_today
    runs.where(created_at: Time.current.all_day).count
  end

  def push_event_data
    { id: id, board_id: board_id, trigger_type: trigger_type, trigger_config: trigger_config, actions: actions, active: active,
      needs_attention: needs_attention }
  end

  private

  def inherit_account
    self.account_id ||= board&.account_id
  end

  def normalise_actions
    self.actions = Custom::Kanban::AutomationAction.normalize(actions)
  end

  def actions_are_valid
    return errors.add(:actions, :empty) if actions.blank?
    return errors.add(:actions, :too_many, count: MAX_ACTIONS) if actions.size > MAX_ACTIONS

    steps.each_with_index do |step, index|
      step.errors(self).each { |problem| errors.add(:actions, :"step_#{problem}", position: index + 1) }
    end
  end
end
