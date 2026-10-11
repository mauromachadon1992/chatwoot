# An entry of the account's catalog. Cards copy it into an item when it is added, so editing
# or deactivating a product never changes a deal that already holds it.
class Custom::Kanban::Product < ApplicationRecord
  UNITS = %w[un m m2 m3 kg t l cx pc sc par kit h srv].freeze

  belongs_to :account
  has_many :card_items, class_name: 'Custom::Kanban::CardItem', dependent: :nullify

  validates :name, presence: true, length: { maximum: 160 }
  validates :sku, length: { maximum: 60 }, uniqueness: { scope: :account_id, allow_nil: true }
  validates :unit, inclusion: { in: UNITS }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :normalize

  scope :ordered, -> { order(Arel.sql('LOWER(name)'), :id) }
  scope :active, -> { where(active: true) }

  def self.search(term)
    return all if term.blank?

    like = "%#{sanitize_sql_like(term.strip)}%"
    where('flow_kanban_products.name ILIKE :like OR flow_kanban_products.sku ILIKE :like', like: like)
  end

  def push_event_data
    { id: id, name: name, sku: sku, unit: unit, price_cents: price_cents, active: active }
  end

  private

  def normalize
    self.name = name&.strip
    self.sku = sku&.strip.presence
  end
end
