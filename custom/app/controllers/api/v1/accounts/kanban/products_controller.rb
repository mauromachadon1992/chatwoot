# The account's product catalog. The list is searched and paged on the server, since a store's
# catalog runs into thousands of entries; `active=true` is what the card's product picker asks for.
class Api::V1::Accounts::Kanban::ProductsController < Api::V1::Accounts::Kanban::BaseController
  PER_PAGE = 25

  before_action :product, only: [:update, :destroy]

  def index
    authorize Custom::Kanban::Product
    products = Custom::Kanban::Product.where(account: Current.account).search(params[:q])
    products = products.active if ActiveModel::Type::Boolean.new.cast(params[:active])
    page = [params[:page].to_i, 1].max

    render json: {
      payload: products.ordered.offset((page - 1) * PER_PAGE).limit(PER_PAGE).map(&:push_event_data),
      meta: { count: products.count, page: page, per_page: PER_PAGE }
    }
  end

  def create
    product = Custom::Kanban::Product.new(product_params.merge(account: Current.account))
    authorize product
    product.save!
    render json: { payload: product.push_event_data }
  end

  def update
    @product.update!(product_params)
    render json: { payload: @product.push_event_data }
  end

  # Deals that hold the product keep their copy of it.
  def destroy
    @product.destroy!
    head :ok
  end

  private

  def product
    @product = Custom::Kanban::Product.where(account: Current.account).find(params[:id])
    authorize @product
  end

  def product_params
    params.permit(:name, :sku, :unit, :price_cents, :active)
  end
end
