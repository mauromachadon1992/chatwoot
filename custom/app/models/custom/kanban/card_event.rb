# One line of a deal's history. Append-only: written by the models where the change happens,
# read by the card panel's History, and later by webhooks and the AI summary (ROADMAP.md).
# `data` holds what the sentence needs as it was then (names, not only ids), so renaming a
# stage or deleting a task does not rewrite the past.
class Custom::Kanban::CardEvent < ApplicationRecord
  KINDS = %w[created stage_moved value_changed assignee_changed task_created task_completed
             conversation_linked quote_prepared task_reopened automation_ran].freeze

  belongs_to :account
  belongs_to :card, class_name: 'Custom::Kanban::Card'
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # The actor is whoever is signed in; a rule or a job leaves it empty.
  def self.record!(card, kind, data = {}, user: Current.user)
    create!(account_id: card.account_id, card: card, user: user, kind: kind, data: data.compact)
  end

  def push_event_data
    { id: id, kind: kind, data: data, created_at: created_at.to_i, user: user && { id: user.id, name: user.name, thumbnail: user.avatar_url } }
  end
end
