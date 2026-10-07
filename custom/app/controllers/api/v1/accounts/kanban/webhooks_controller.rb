# The account's webhooks (administrators only; see Custom::Kanban::Webhook). The secret is in the
# create response and nowhere else.
class Api::V1::Accounts::Kanban::WebhooksController < Api::V1::Accounts::Kanban::BaseController
  before_action :webhook, only: [:update, :destroy, :deliveries, :test]

  def index
    authorize Custom::Kanban::Webhook
    webhooks = Custom::Kanban::Webhook.where(account: Current.account).ordered.to_a
    render json: { payload: webhooks.map { |hook| row(hook, last_deliveries[hook.id]) },
                   meta: { events: Custom::Kanban::Webhook::EVENTS, max: Custom::Kanban::Webhook::MAX_PER_ACCOUNT } }
  end

  def create
    hook = Custom::Kanban::Webhook.new(webhook_params.merge(account: Current.account))
    authorize hook
    hook.save!
    render json: { payload: row(hook, nil), secret: hook.secret }
  end

  def update
    @webhook.update!(webhook_params)
    render json: { payload: row(@webhook, last_deliveries[@webhook.id]) }
  end

  def destroy
    @webhook.destroy!
    head :ok
  end

  def deliveries
    list = @webhook.deliveries.newest_first.limit(Custom::Kanban::WebhookDelivery::LISTED)
    render json: { payload: list.map(&:push_event_data) }
  end

  # One real try, now, with a "ping" event: the administrator sees the answer without waiting.
  def test
    delivery = @webhook.deliveries.create!(event: 'ping', payload: Custom::Kanban::WebhookDispatcher.payload_for(Current.account, 'ping'))
    result = Custom::Kanban::WebhookSender.new(@webhook, delivery).call
    delivery.update!(attempts: 1, http_status: result.http_status, error: result.error, duration_ms: result.duration_ms,
                     status: result.success? ? 'success' : 'failed', delivered_at: (Time.current if result.success?))
    render json: { payload: delivery.push_event_data }
  end

  private

  def webhook
    @webhook = Custom::Kanban::Webhook.where(account: Current.account).find(params[:id])
    authorize @webhook
  end

  def webhook_params
    params.permit(:url, :active, events: [])
  end

  def last_deliveries
    @last_deliveries ||= begin
      ids = Custom::Kanban::WebhookDelivery.where(webhook_id: Custom::Kanban::Webhook.where(account: Current.account).select(:id))
                                           .group(:webhook_id).maximum(:id).values
      Custom::Kanban::WebhookDelivery.where(id: ids).index_by(&:webhook_id)
    end
  end

  def row(hook, delivery)
    hook.push_event_data.merge(last_delivery: delivery&.push_event_data)
  end
end
