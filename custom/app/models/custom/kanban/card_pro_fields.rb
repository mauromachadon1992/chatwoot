# The card fields of the Pro dialect: a priority, a start and a due time, free attributes and labels.
# They are what the fazer.ai agents read and write on a deal, and what a person edits in the card
# panel; the limits keep an agent's free text from growing a row without bound.
module Custom::Kanban::CardProFields
  extend ActiveSupport::Concern

  PRIORITIES = %w[urgent high medium low].freeze
  LABELS_MAX = 20
  LABEL_MAX_LENGTH = 50
  ATTRIBUTES_MAX = 50
  ATTRIBUTE_KEY_MAX_LENGTH = 60
  ATTRIBUTES_MAX_BYTES = 10_000

  included do
    before_validation :normalize_labels
    validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true
    validate :start_before_due
    validate :custom_attributes_are_small
    validate :labels_are_short
    after_update :record_pro_field_events
  end

  def pro_data
    { priority: priority, start_at: start_at&.iso8601, due_at: due_at&.iso8601, labels: labels, custom_attributes: custom_attributes }
  end

  private

  # One line of history for each kind of change, so a person reads "priority: high" and not a diff.
  def record_pro_field_events
    event = Custom::Kanban::CardEvent
    event.record!(self, 'priority_changed', { from: saved_changes['priority'].first, to: priority }) if saved_change_to_priority?
    event.record!(self, 'dates_changed', dates_change) if saved_change_to_start_at? || saved_change_to_due_at?
    event.record!(self, 'labels_changed', labels_change) if saved_change_to_labels?
    event.record!(self, 'attributes_changed', { keys: changed_attribute_keys }) if saved_change_to_custom_attributes?
  end

  def dates_change
    { start_at: start_at&.iso8601, due_at: due_at&.iso8601, from_start_at: saved_changes['start_at']&.first&.iso8601,
      from_due_at: saved_changes['due_at']&.first&.iso8601 }
  end

  def labels_change
    before = saved_changes['labels'].first
    { added: labels - before, removed: before - labels }
  end

  # The names of the attributes that changed, never their values (an agent may keep personal data there).
  def changed_attribute_keys
    before = saved_changes['custom_attributes'].first.to_h
    (before.keys | custom_attributes.keys).reject { |key| before[key] == custom_attributes[key] }.first(ATTRIBUTES_MAX)
  end

  def normalize_labels
    self.labels = Array(labels).map { |label| label.to_s.squish }.compact_blank.uniq
  end

  def start_before_due
    errors.add(:start_at, :after_due) if start_at && due_at && start_at > due_at
  end

  def custom_attributes_are_small
    return errors.add(:custom_attributes, :invalid) unless custom_attributes.is_a?(Hash)

    too_many = custom_attributes.size > ATTRIBUTES_MAX
    long_key = custom_attributes.keys.any? { |key| key.to_s.length > ATTRIBUTE_KEY_MAX_LENGTH || key.to_s.blank? }
    errors.add(:custom_attributes, :too_many, count: ATTRIBUTES_MAX) if too_many
    errors.add(:custom_attributes, :bad_key, max: ATTRIBUTE_KEY_MAX_LENGTH) if long_key
    errors.add(:custom_attributes, :too_big) if custom_attributes.to_json.bytesize > ATTRIBUTES_MAX_BYTES
  end

  def labels_are_short
    errors.add(:labels, :too_many, count: LABELS_MAX) if labels.size > LABELS_MAX
    errors.add(:labels, :too_long, max: LABEL_MAX_LENGTH) if labels.any? { |label| label.length > LABEL_MAX_LENGTH }
  end
end
