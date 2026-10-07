# How a deal is expected to end, and why it ended lost: the close date the forecast reads, and
# the lost reason and note, which belong to the deal's stay in a lost stage only.
module Custom::Kanban::CardOutcome
  extend ActiveSupport::Concern

  LOST_NOTE_MAX_LENGTH = 500
  # A close date a forecast can use: not before the product existed, not a decade out.
  EXPECTED_CLOSE_RANGE = -> { Date.new(2000, 1, 1)..10.years.from_now.to_date }

  included do
    belongs_to :lost_reason, class_name: 'Custom::Kanban::LostReason', optional: true

    validates :lost_note, length: { maximum: LOST_NOTE_MAX_LENGTH }
    validate :lost_reason_belongs_to_account
    validate :expected_close_in_range

    # Moving out of a lost stage forgets why the deal was lost.
    before_save :clear_lost_reason, if: -> { stage_id_changed? && !stage&.stage_type_lost? }
  end

  private

  def clear_lost_reason
    self.lost_reason = nil
    self.lost_note = nil
  end

  def lost_reason_belongs_to_account
    errors.add(:lost_reason, :invalid) if lost_reason && lost_reason.account_id != account_id
  end

  def expected_close_in_range
    errors.add(:expected_close_on, :invalid) if expected_close_on && !EXPECTED_CLOSE_RANGE.call.cover?(expected_close_on)
  end
end
