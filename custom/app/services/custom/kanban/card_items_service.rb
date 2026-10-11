# Changes the product lines of a deal and keeps its value equal to their sum, in one
# transaction, so a reader never sees lines and value disagree.
class Custom::Kanban::CardItemsService
  EDITABLE = %i[quantity unit_price_cents discount_percent].freeze

  def initialize(card)
    @card = card
  end

  # Only active products can be added; lines already on deals keep inactive ones.
  def add(product:, attributes: {})
    raise ActiveRecord::RecordNotFound unless product.active?

    change do
      item = @card.items.new(account: @card.account)
      item.copy_product(product)
      item.assign_attributes(attributes.slice(*EDITABLE))
      item.save!
    end
  end

  def update(item, attributes)
    change { item.update!(attributes.slice(*EDITABLE)) }
  end

  def remove(item)
    change { item.destroy! }
  end

  private

  def change
    ActiveRecord::Base.transaction do
      @card.lock!
      yield
      @card.reload.recalculate_value!
    end
    @card
  end
end
