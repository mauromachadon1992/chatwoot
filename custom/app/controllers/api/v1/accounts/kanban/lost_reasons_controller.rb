# The account's reasons for losing a deal. Short by nature (a handful), so listed whole.
class Api::V1::Accounts::Kanban::LostReasonsController < Api::V1::Accounts::Kanban::BaseController
  before_action :lost_reason, only: [:update, :destroy]

  def index
    authorize Custom::Kanban::LostReason
    reasons = Custom::Kanban::LostReason.where(account: Current.account).ordered
    counts = Custom::Kanban::Card.where(account: Current.account, lost_reason_id: reasons.select(:id)).group(:lost_reason_id).count
    render json: { payload: reasons.map { |reason| reason.push_event_data.merge(deals_count: counts.fetch(reason.id, 0)) } }
  end

  def create
    reason = Custom::Kanban::LostReason.new(name: params.require(:name), account: Current.account)
    authorize reason
    reason.save!
    render json: { payload: reason.push_event_data.merge(deals_count: 0) }
  end

  def update
    @lost_reason.update!(name: params.require(:name))
    render json: { payload: @lost_reason.push_event_data }
  end

  # The deals keep being lost; they only lose the reason (the foreign key empties it).
  def destroy
    @lost_reason.destroy!
    head :ok
  end

  private

  def lost_reason
    @lost_reason = Custom::Kanban::LostReason.where(account: Current.account).find(params[:id])
    authorize @lost_reason
  end
end
