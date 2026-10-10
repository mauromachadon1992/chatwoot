# Kanban phase 2: what a deal is worth (a value, or the sum of its products), the account's
# product catalog, and the stage history the funnel report reads.
#
# Money is stored in minor units (cents) as bigint, so sums are exact in SQL and in the
# dashboard; the account has one currency (accounts.settings.flow_kanban_currency).
class AddValuesToFlowKanban < ActiveRecord::Migration[7.1]
  def up
    create_products
    create_card_items
    add_card_value
    create_stage_transitions
    backfill_stage_transitions
  end

  def down
    drop_table :flow_kanban_stage_transitions
    remove_column :flow_kanban_cards, :items_count
    remove_column :flow_kanban_cards, :value_cents
    drop_table :flow_kanban_card_items
    drop_table :flow_kanban_products
  end

  private

  def create_products
    create_table :flow_kanban_products do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :sku
      t.string :unit, null: false, default: 'un'
      t.bigint :price_cents, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index [:account_id, :name]
      t.index [:account_id, :sku], unique: true, where: 'sku IS NOT NULL'
    end
  end

  # An item copies the product's name, code, unit and price when it is added: changing the
  # catalog later never rewrites a deal that was already quoted.
  def create_card_items
    create_table :flow_kanban_card_items do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :card, null: false, foreign_key: { to_table: :flow_kanban_cards, on_delete: :cascade }
      t.references :product, foreign_key: { to_table: :flow_kanban_products, on_delete: :nullify }
      t.string :name, null: false
      t.string :sku
      t.string :unit, null: false, default: 'un'
      t.decimal :quantity, precision: 12, scale: 3, null: false, default: 1
      t.bigint :unit_price_cents, null: false, default: 0
      t.decimal :discount_percent, precision: 5, scale: 2, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [:card_id, :position]
    end
  end

  def add_card_value
    add_column :flow_kanban_cards, :value_cents, :bigint, null: false, default: 0
    add_column :flow_kanban_cards, :items_count, :integer, null: false, default: 0
  end

  # One row each time a card enters a stage (from_stage_id is null when it was created there).
  # The stage ids carry no foreign key: deleting a stage keeps the history of what went
  # through it.
  def create_stage_transitions
    create_table :flow_kanban_stage_transitions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :board, null: false, foreign_key: { to_table: :flow_kanban_boards, on_delete: :cascade }
      t.references :card, null: false, foreign_key: { to_table: :flow_kanban_cards, on_delete: :cascade }
      t.bigint :from_stage_id
      t.bigint :to_stage_id, null: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.datetime :created_at, null: false
      t.index [:board_id, :created_at]
      t.index [:card_id, :created_at]
      t.index :to_stage_id
    end
  end

  # Cards from phase 1 have no history: each one gets a single entry into its current stage,
  # dated when it got there, so the report starts from what is known instead of from nothing.
  def backfill_stage_transitions
    execute <<~SQL.squish
      INSERT INTO flow_kanban_stage_transitions (account_id, board_id, card_id, to_stage_id, created_at)
      SELECT account_id, board_id, id, stage_id, COALESCE(stage_changed_at, created_at)
      FROM flow_kanban_cards
    SQL
  end
end
