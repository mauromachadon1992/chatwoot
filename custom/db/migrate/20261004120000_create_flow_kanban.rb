class CreateFlowKanban < ActiveRecord::Migration[7.1]
  def change
    create_boards
    create_board_restrictions
    create_stages
    create_cards
    create_card_conversations
  end

  private

  def create_boards
    create_table :flow_kanban_boards do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
  end

  # A board with no inbox and no team is visible to every agent of the account.
  def create_board_restrictions
    create_table :flow_kanban_board_inboxes do |t|
      t.references :board, null: false, foreign_key: { to_table: :flow_kanban_boards, on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.index [:board_id, :inbox_id], unique: true
    end

    create_table :flow_kanban_board_teams do |t|
      t.references :board, null: false, foreign_key: { to_table: :flow_kanban_boards, on_delete: :cascade }
      t.references :team, null: false, foreign_key: { on_delete: :cascade }
      t.index [:board_id, :team_id], unique: true
    end
  end

  def create_stages
    create_table :flow_kanban_stages do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :board, null: false, foreign_key: { to_table: :flow_kanban_boards, on_delete: :cascade }
      t.string :name, null: false
      t.string :color, null: false, default: '#6B7280'
      t.integer :stage_type, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [:board_id, :position]
    end
  end

  def create_cards
    create_table :flow_kanban_cards do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :board, null: false, foreign_key: { to_table: :flow_kanban_boards, on_delete: :cascade }
      t.references :stage, null: false, foreign_key: { to_table: :flow_kanban_stages }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :assignee, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :title, null: false
      t.text :description
      t.float :position, null: false, default: 0
      t.datetime :stage_changed_at
      t.timestamps
      t.index [:stage_id, :position]
      t.index [:board_id, :assignee_id]
    end
  end

  # A conversation sits on at most one card per board, but may be on cards of other boards.
  def create_card_conversations
    create_table :flow_kanban_card_conversations do |t|
      t.references :card, null: false, foreign_key: { to_table: :flow_kanban_cards, on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :board, null: false, foreign_key: { to_table: :flow_kanban_boards, on_delete: :cascade }
      t.timestamps
      t.index [:board_id, :conversation_id], unique: true
    end
  end
end
