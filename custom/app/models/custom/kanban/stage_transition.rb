# The stage history of a card: one row each time it enters a stage. The funnel report reads it
# to tell how far deals got and how long they stayed; nothing else writes or changes it.
class Custom::Kanban::StageTransition < ApplicationRecord
  belongs_to :account
  belongs_to :board, class_name: 'Custom::Kanban::Board'
  belongs_to :card, class_name: 'Custom::Kanban::Card'
  belongs_to :user, optional: true

  # Recorded for a whole column at once when a deleted stage hands its cards to another one.
  def self.record_bulk!(cards:, from_stage:, to_stage:, user:, at: Time.current)
    rows = cards.map do |card|
      { account_id: card.account_id, board_id: card.board_id, card_id: card.id, from_stage_id: from_stage.id,
        to_stage_id: to_stage.id, user_id: user&.id, created_at: at }
    end
    insert_all(rows) if rows.any? # rubocop:disable Rails/SkipsModelValidations
  end
end
