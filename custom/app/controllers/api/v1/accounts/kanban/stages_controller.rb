class Api::V1::Accounts::Kanban::StagesController < Api::V1::Accounts::Kanban::BaseController
  before_action :board
  before_action :stage, only: [:update, :destroy]

  def create
    stage = @board.stages.new(stage_params)
    authorize stage
    stage.save!
    broadcast_board
    render json: { payload: stage.push_event_data }
  end

  def update
    @stage.update!(stage_params)
    broadcast_board
    render json: { payload: @stage.push_event_data }
  end

  # A stage that still holds cards hands them to `move_to_stage_id` first, so deleting a
  # column never deletes deals.
  def destroy
    ActiveRecord::Base.transaction do
      move_cards_out if @stage.cards.exists?
      @stage.destroy!
    end
    broadcast_board
    head :ok
  end

  def reorder
    authorize Custom::Kanban::Stage, :reorder?
    stage_ids = Array(params[:stage_ids]).map(&:to_i)
    stages = @board.stages.where(id: stage_ids).index_by(&:id)
    ActiveRecord::Base.transaction do
      stage_ids.each_with_index { |id, index| stages[id]&.update!(position: index) }
    end
    broadcast_board
    render json: { payload: @board.reload.push_event_data }
  end

  private

  def board
    @board = find_visible_board(params[:board_id])
  end

  def stage
    @stage = @board.stages.find(params[:id])
    authorize @stage
  end

  def stage_params
    params.permit(:name, :color, :stage_type)
  end

  def move_cards_out
    target = @board.stages.where.not(id: @stage.id).find(params.require(:move_to_stage_id))
    # One statement for the whole column; the cards stay valid since the target is on the same board.
    @stage.cards.update_all(stage_id: target.id, stage_changed_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    Custom::Kanban::Card.renumber!(target)
  end

  def broadcast_board
    Custom::Kanban::Broadcaster.board_updated(@board.reload)
  end
end
