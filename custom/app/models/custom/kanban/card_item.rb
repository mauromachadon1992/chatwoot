# A product line on a deal: a copy of the catalog entry at the time it was added, with its own
# quantity, unit price and discount. The card's value is the sum of these lines.
class Custom::Kanban::CardItem < ApplicationRecord
  MAX_QUANTITY = 999_999_999

  belongs_to :account
  belongs_to :card, class_name: 'Custom::Kanban::Card', counter_cache: :items_count
  belongs_to :product, class_name: 'Custom::Kanban::Product', optional: true

  validates :name, presence: true, length: { maximum: 160 }
  validates :unit, inclusion: { in: Custom::Kanban::Product::UNITS }
  validates :quantity, numericality: { greater_than: 0, less_than_or_equal_to: MAX_QUANTITY }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :product_belongs_to_account

  before_validation :inherit_account, on: :create
  before_create :append_to_card

  scope :ordered, -> { order(:position, :id) }

  # Rounded to the cent once per line, so the card total is the sum the agent sees.
  def total_cents
    (quantity * unit_price_cents * (100 - discount_percent) / 100).round.to_i
  end

  # Starts the line from a catalog entry; the agent may then change quantity, price and discount.
  def copy_product(product)
    self.product = product
    self.name = product.name
    self.sku = product.sku
    self.unit = product.unit
    self.unit_price_cents = product.price_cents
  end

  def push_event_data
    {
      id: id,
      product_id: product_id,
      name: name,
      sku: sku,
      unit: unit,
      quantity: quantity.to_s,
      unit_price_cents: unit_price_cents,
      discount_percent: discount_percent.to_s,
      total_cents: total_cents
    }
  end

  private

  def inherit_account
    self.account_id ||= card&.account_id
  end

  def append_to_card
    self.position = (card.items.maximum(:position) || -1) + 1
  end

  def product_belongs_to_account
    errors.add(:product, :invalid) if product && product.account_id != account_id
  end
end
