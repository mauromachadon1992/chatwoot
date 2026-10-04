class Api::V1::Accounts::Kanban::BoardsController < Api::V1::Accounts::Kanban::BaseController
  DEFAULT_STAGES = [
    { key: 'new', color: '#3B82F6', stage_type: :open },
    { key: 'in_progress', color: '#F59E0B', stage_type: :open },
    { key: 'won', color: '#10B981', stage_type: :won },
    { key: 'lost', color: '#EF4444', stage_type: :lost }
  ].freeze

  before_action :board, only: [:show, :update, :destroy]

  def index
    authorize Custom::Kanban::Board
    boards = visible_boards.ordered.includes(:board_inboxes, :board_teams, :stages)
    render json: { payload: boards.map(&:push_event_data) }
  end

  def show
    render json: { payload: @board.push_event_data }
  end

  def create
    board = Custom::Kanban::Board.new(board_params.merge(account: Current.account, created_by: Current.user))
    authorize board
    ActiveRecord::Base.transaction do
      board.save!
      assign_restrictions(board)
      create_default_stages(board)
    end
    Custom::Kanban::Broadcaster.board_updated(board.reload)
    render json: { payload: board.push_event_data }
  end

  def update
    # Whoever loses access with this change still has to hear about it to drop the board.
    previous_tokens = @board.member_tokens
    ActiveRecord::Base.transaction do
      @board.update!(board_params)
      assign_restrictions(@board)
    end
    Custom::Kanban::Broadcaster.board_updated(@board.reload, extra_tokens: previous_tokens)
    render json: { payload: @board.push_event_data }
  end

  def destroy
    tokens = @board.member_tokens
    @board.destroy!
    Custom::Kanban::Broadcaster.board_deleted(@board, tokens)
    head :ok
  end

  private

  def board
    @board = find_visible_board(params[:id])
    authorize @board
  end

  def board_params
    params.permit(:name, :description, :position)
  end

  def assign_restrictions(board)
    board.inbox_ids = Current.account.inboxes.where(id: params[:inbox_ids]).pluck(:id) if params.key?(:inbox_ids)
    board.team_ids = Current.account.teams.where(id: params[:team_ids]).pluck(:id) if params.key?(:team_ids)
  end

  def create_default_stages(board)
    DEFAULT_STAGES.each_with_index do |stage, index|
      board.stages.create!(
        name: I18n.t("flow_kanban.default_stages.#{stage[:key]}"),
        color: stage[:color],
        stage_type: stage[:stage_type],
        position: index
      )
    end
  end
end
