# A request for an AI summary of a deal and what became of it. The text itself is never stored: it
# lives in the agent's screen until they accept it (into the deal) or throw it away.
class Custom::Kanban::AiDraft < ApplicationRecord
  STATUSES = %w[pending generated accepted discarded failed].freeze
  # What an agent may do with a generated draft.
  DECISIONS = %w[accepted discarded].freeze
  # Each request costs money, so an agent gets this many an hour.
  PER_HOUR = 10
  KEPT_FOR = 90.days

  belongs_to :account
  belongs_to :card, class_name: 'Custom::Kanban::Card'
  belongs_to :user

  validates :status, inclusion: { in: STATUSES }

  scope :recent_for, ->(user, now = Time.current) { where(user_id: user.id, created_at: (now - 1.hour)..now) }

  # Minutes until the agent has a request again, or nil when they have one now.
  def self.wait_minutes(user, now = Time.current)
    recent = recent_for(user, now).order(:created_at)
    return nil if recent.count < PER_HOUR

    oldest = recent.first.created_at
    [((oldest + 1.hour - now) / 60).ceil, 1].max
  end

  # Accepting or discarding a draft counts once: the first answer stands.
  def decide!(decision)
    claimed = self.class.where(id: id, status: 'generated').update_all(status: decision, decided_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    claimed.positive?
  end
end
