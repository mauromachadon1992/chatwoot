# What a rule's trigger needs to be valid: its settings, by trigger type. Included by
# StageAutomation, which keeps the rest of the rule.
module Custom::Kanban::AutomationTrigger
  extend ActiveSupport::Concern

  LABEL_MAX_LENGTH = 100
  NO_REPLY_HOURS = (1..720)
  NO_REPLY_SIDES = %w[customer agent].freeze

  included do
    validates :trigger_type, inclusion: { in: Custom::Kanban::StageAutomation::TRIGGER_TYPES }
    validate :trigger_config_matches_trigger
    before_validation :normalise_trigger_config
  end

  def matches_status?(status)
    trigger_type == 'conversation_status_changed' && trigger_config['status'] == status.to_s
  end

  def matches_label?(label)
    trigger_type == 'label_added' && trigger_config['label'] == label
  end

  private

  def normalise_trigger_config
    return unless trigger_config.is_a?(Hash) && trigger_type == 'no_reply' && trigger_config.key?('hours')

    self.trigger_config = trigger_config.merge('hours' => Integer(trigger_config['hours'], exception: false))
  end

  def trigger_config_matches_trigger
    config = trigger_config.is_a?(Hash) ? trigger_config : {}
    problem = send(:"#{trigger_type}_problem", config) if respond_to?(:"#{trigger_type}_problem", true)
    errors.add(:trigger_config, problem) if problem
  end

  def conversation_status_changed_problem(config)
    :invalid unless Conversation.statuses.key?(config['status'])
  end

  def label_added_problem(config)
    label = config['label']
    :invalid unless label.is_a?(String) && label.present? && label.length <= LABEL_MAX_LENGTH
  end

  def no_reply_problem(config)
    :no_reply unless NO_REPLY_HOURS.cover?(config['hours']) && NO_REPLY_SIDES.include?(config['side'])
  end
end
