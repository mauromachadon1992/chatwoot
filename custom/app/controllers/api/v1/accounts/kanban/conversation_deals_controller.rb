# The deal of a conversation and its product lines, for the fazer.ai agents (capability `deal.items`).
# An agent knows the conversation it is answering, not the card, so these routes are keyed by the
# conversation's display id and resolve the card the way the conversation's `kanban_task` does: the
# most recently updated open deal on a board the caller sees. The agent can never name another card.
#
# The price always comes from the catalog and the discount stays at zero: only the quantity is the
# agent's. Adding a product that is already on the deal sets its quantity, so there is one line per
# product.
class Api::V1::Accounts::Kanban::ConversationDealsController < Api::V1::Accounts::Kanban::BaseController
  MAX_LINES = 50

  before_action :conversation
  before_action :deal

  def show
    authorize @card, :show?
    render_deal
  end

  # The quote text and totals, computed on the server; the agent sends it, it does not calculate.
  def quote
    authorize @card, :show?
    render json: { payload: Custom::Kanban::QuotePreview.new(@card, account: Current.account, user: Current.user, locale: params[:locale]) }
  end

  def add_item
    authorize @card, :update?
    product = Custom::Kanban::Product.where(account: Current.account).find(params.require(:product_id))
    quantity = quantity_param
    return unless quantity

    line = @card.items.find_by(product_id: product.id)
    if line
      service.update(line, quantity: quantity)
    else
      return render_problem(:too_many_lines, max: MAX_LINES) if @card.items.count >= MAX_LINES

      service.add(product: product, attributes: { quantity: quantity })
    end
    render_deal
  end

  def remove_item
    authorize @card, :update?
    service.remove(@card.items.find_by!(product_id: params[:product_id]))
    render_deal
  end

  private

  def conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:display_id])
    authorize @conversation, :show?
  end

  def deal
    scope = cards_scope.where(board_id: visible_boards.select(:id))
    @card = Custom::Kanban::ProSerializer.open_card_of(@conversation, scope)
    render_problem(:no_deal, status: :not_found) unless @card
  end

  def service
    Custom::Kanban::CardItemsService.new(@card)
  end

  # A number the catalog's unit makes sense of (12, 12.5, "12,5" is not accepted: the agent sends JSON numbers).
  def quantity_param
    quantity = BigDecimal(params.require(:quantity).to_s)
    return quantity if quantity.positive?

    render_problem(:invalid_quantity)
    nil
  rescue ArgumentError
    render_problem(:invalid_quantity)
    nil
  end

  def render_deal
    card = cards_scope.find(@card.id)
    Custom::Kanban::Broadcaster.card_updated(card)
    render json: { payload: card.push_event_data(with_items: true) }
  end

  def render_problem(key, status: :unprocessable_content, **)
    render json: { message: I18n.t("flow_kanban.pro.#{key}", **) }, status: status
  end
end
