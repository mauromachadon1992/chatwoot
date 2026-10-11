# The product lines of a deal. Whoever may work the card may change them; every change answers
# with the card and its lines, and tells the board the new value.
class Api::V1::Accounts::Kanban::CardItemsController < Api::V1::Accounts::Kanban::BaseController
  before_action :card
  before_action :item, only: [:update, :destroy]

  def create
    product = Custom::Kanban::Product.where(account: Current.account).find(params.require(:product_id))
    service.add(product: product, attributes: item_params)
    broadcast_updated
  end

  def update
    service.update(@item, item_params)
    broadcast_updated
  end

  def destroy
    service.remove(@item)
    broadcast_updated
  end

  private

  def card
    @card = Custom::Kanban::Card.where(board_id: visible_boards.select(:id)).find(params[:card_id])
    authorize @card, :update?
  end

  def item
    @item = @card.items.find(params[:id])
  end

  def service
    Custom::Kanban::CardItemsService.new(@card)
  end

  def item_params
    params.permit(:quantity, :unit_price_cents, :discount_percent).to_h.symbolize_keys
  end

  def broadcast_updated
    card = cards_scope.find(@card.id)
    Custom::Kanban::Broadcaster.card_updated(card)
    render json: { payload: card.push_event_data(with_items: true) }
  end
end
