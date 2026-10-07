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
    params.permit(:name, :color, :stage_type, :stale_after_days)
  end

  def move_cards_out
    target = @board.stages.where.not(id: @stage.id).find(params.require(:move_to_stage_id))
    now = Time.current
    # The column's history first: the update below skips the card callbacks that record it.
    Custom::Kanban::StageTransition.record_bulk!(cards: @stage.cards, from_stage: @stage, to_stage: target, user: Current.user, at: now)
    # One statement for the whole column; the cards stay valid since the target is on the same board.
    @stage.cards.update_all(stage_id: target.id, stage_changed_at: now, stale_notified_at: nil, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    Custom::Kanban::Card.renumber!(target)
  end

  def broadcast_board
    Custom::Kanban::Broadcaster.board_updated(@board.reload)
  end
end
