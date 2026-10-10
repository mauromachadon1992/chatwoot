class Api::V1::Accounts::Kanban::BoardsController < Api::V1::Accounts::Kanban::BaseController
  DEFAULT_STAGES = [
    { key: 'new', color: '#3B82F6', stage_type: :open },
    { key: 'in_progress', color: '#F59E0B', stage_type: :open },
    { key: 'won', color: '#10B981', stage_type: :won },
    { key: 'lost', color: '#EF4444', stage_type: :lost }
  ].freeze

  before_action :board, only: [:show, :update, :destroy, :update_inboxes, :update_agents]

  def index
    authorize Custom::Kanban::Board
    boards = visible_boards.ordered.includes(:board_inboxes, :board_teams, :board_agents, :stages)
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
      create_default_stages(board) unless pro_dialect?
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

  # The Pro dialect's bindings (operations 6 and 7): the board is shared with exactly these inboxes, or
  # these agents. A diff, so sending the same list again changes nothing.
  def update_inboxes
    rebind(:inbox_ids) { |ids| Current.account.inboxes.where(id: ids).pluck(:id) }
  end

  def update_agents
    rebind(:agent_ids) { |ids| Current.account.users.where(id: ids).pluck(:id) }
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
    authorize @board, (params[:action].start_with?('update_') ? :update? : nil)
  end

  def rebind(attribute)
    previous_tokens = @board.member_tokens
    @board.update!(attribute => yield(Array(params[attribute]).compact_blank.map(&:to_i)))
    Custom::Kanban::Broadcaster.board_updated(@board.reload, extra_tokens: previous_tokens)
    render json: { payload: @board.push_event_data }
  end

  # `{board: {...}}` is the Pro dialect's root key; the dashboard sends the fields flat. A board made
  # with the root key gets no default stages: the caller (the Agents' funnel wizard) creates its own
  # steps, and Flow's four would sit beside them.
  def board_source
    params[:board].is_a?(ActionController::Parameters) ? params[:board] : params
  end

  def pro_dialect?
    params[:board].is_a?(ActionController::Parameters)
  end

  def board_params
    board_source.permit(:name, :description, :position, auto_create: [:enabled, :daily_cap, { inbox_ids: [] }])
  end

  # Inboxes, teams and agents the board is shared with: a key left out keeps what it had, and ids of
  # another account are dropped.
  def assign_restrictions(board)
    { inbox_ids: Current.account.inboxes, team_ids: Current.account.teams, agent_ids: Current.account.users }.each do |key, scope|
      board.public_send("#{key}=", scope.where(id: params[key]).pluck(:id)) if params.key?(key)
    end
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
