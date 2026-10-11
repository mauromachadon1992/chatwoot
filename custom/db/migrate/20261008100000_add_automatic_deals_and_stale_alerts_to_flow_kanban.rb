# Kanban sprint 2: deals a new conversation opens on its own, and deals that stay too long in a
# stage.
#
# - boards.settings: the board's automatic-deal rule (on/off, inboxes, daily cap).
# - cards.source / needs_review: where a deal came from, and whether an agent has looked at an
#   automatic one yet.
# - stages.stale_after_days: how long a deal may stay in an open stage before it is flagged.
# - cards.stale_notified_at: the one notification of a stall was sent (cleared when it moves).
class AddAutomaticDealsAndStaleAlertsToFlowKanban < ActiveRecord::Migration[7.1]
  def change
    add_column :flow_kanban_boards, :settings, :jsonb, null: false, default: {}

    add_column :flow_kanban_cards, :source, :string, null: false, default: 'manual'
    add_column :flow_kanban_cards, :needs_review, :boolean, null: false, default: false
    add_column :flow_kanban_cards, :stale_notified_at, :datetime
    # The daily cap counts a board's automatic deals of the day.
    add_index :flow_kanban_cards, [:board_id, :source, :created_at], name: 'index_flow_kanban_cards_on_board_source_created'
    # The stalled-deal job and filter read a stage's cards by when they entered it.
    add_index :flow_kanban_cards, [:stage_id, :stage_changed_at], name: 'index_flow_kanban_cards_on_stage_and_changed'

    add_column :flow_kanban_stages, :stale_after_days, :integer
  end
end
