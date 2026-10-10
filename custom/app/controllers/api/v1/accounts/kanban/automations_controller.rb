# A board's rules: a trigger and an ordered list of actions. Administrators only: a rule acts on
# other people's deals. `runs` is the log of what the rules did lately, read from the deals' history.
class Api::V1::Accounts::Kanban::AutomationsController < Api::V1::Accounts::Kanban::BaseController
  RUNS_SHOWN = 50

  before_action :board
  before_action :automation, only: [:update, :destroy]

  def index
    authorize Custom::Kanban::StageAutomation
    render json: { payload: @board.stage_automations.ordered.map(&:push_event_data) }
  end

  def create
    automation = @board.stage_automations.new(automation_params)
    authorize automation
    automation.save!
    render json: { payload: automation.push_event_data }, status: :created
  end

  def update
    @automation.update!(automation_params)
    render json: { payload: @automation.push_event_data }
  end

  def destroy
    @automation.destroy!
    head :ok
  end

  # What the rules did, newest first, each line with the deal it was about.
  def runs
    authorize Custom::Kanban::StageAutomation, :index?
    events = Custom::Kanban::CardEvent.where(kind: 'automation_ran', card_id: @board.cards.select(:id))
                                      .includes(:card).newest_first.limit(RUNS_SHOWN)
    render json: { payload: events.map { |event| run_row(event) } }
  end

  private

  def board
    @board = find_visible_board(params[:board_id])
  end

  def automation
    @automation = @board.stage_automations.find(params[:id])
    authorize @automation
  end

  def run_row(event)
    event.push_event_data.merge(card: { id: event.card_id, title: event.card.title })
  end

  # The actions are an array of hashes whose keys depend on their type; the model drops the rest.
  def automation_params
    params.permit(:trigger_type, :active, trigger_config: [:status, :label, :hours, :side],
                                          actions: [:type, :stage_id, :title, :task_type, :due_in_hours, :assignee, :user_id, :label])
  end
end
