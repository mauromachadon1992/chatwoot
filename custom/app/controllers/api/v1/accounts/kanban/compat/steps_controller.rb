# The funnel's steps in the Pro dialect (operations 4 and 5 of custom/contracts/pro-kanban.md): a
# step is a Flow stage, and `cancelled` means a lost stage. Reading follows the board's
# visibility; creating is for administrators, as it is for stages.
class Api::V1::Accounts::Kanban::Compat::StepsController < Api::V1::Accounts::Kanban::BaseController
  DEFAULT_COLOR = '#64748B'.freeze

  before_action :board

  def index
    render json: { steps: @board.stages.order(:position, :id).map { |stage| Custom::Kanban::ProSerializer.step(stage) } }
  end

  def create
    stage = @board.stages.new({ color: DEFAULT_COLOR }.merge(step_params))
    authorize stage
    stage.save!
    Custom::Kanban::Broadcaster.board_updated(@board.reload)
    render json: Custom::Kanban::ProSerializer.step(stage)
  end

  private

  def board
    @board = find_visible_board(params[:board_id])
  end

  # `{step: {name, color?, description?, cancelled?}}`; a flat body works too. `stage_type` is Flow's
  # own word for what `cancelled` says, and wins when both come.
  def step_params
    source = params[:step].is_a?(ActionController::Parameters) ? params[:step] : params
    attrs = source.permit(:name, :color, :description, :stage_type).to_h.symbolize_keys.compact_blank
    attrs[:stage_type] ||= 'lost' if ActiveModel::Type::Boolean.new.cast(source[:cancelled])
    attrs
  end
end
