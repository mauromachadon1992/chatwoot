# A board's stage automations. Administrators only: a rule moves other people's cards.
class Api::V1::Accounts::Kanban::AutomationsController < Api::V1::Accounts::Kanban::BaseController
  before_action :board
  before_action :automation, only: [:update, :destroy]

  def index
    authorize Custom::Kanban::StageAutomation
    render json: { payload: @board.stage_automations.ordered.map(&:push_event_data) }
  end

  def create
    automation = @board.stage_automations.new(automation_params.to_h.merge(stage: stage_of_board))
    authorize automation
    automation.save!
    render json: { payload: automation.push_event_data }, status: :created
  end

  def update
    @automation.update!(automation_params.to_h.merge(params.key?(:stage_id) ? { stage: stage_of_board } : {}))
    render json: { payload: @automation.push_event_data }
  end

  def destroy
    @automation.destroy!
    head :ok
  end

  private

  def board
    @board = find_visible_board(params[:board_id])
  end

  def automation
    @automation = @board.stage_automations.find(params[:id])
    authorize @automation
  end

  # A stage of this board only: the lookup is what keeps a rule from pointing at another board's stage.
  def stage_of_board
    @board.stages.find(params.require(:stage_id))
  end

  def automation_params
    params.permit(:trigger_type, :active, trigger_config: [:status, :label])
  end
end
