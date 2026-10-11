# The follow-ups of a deal. Whoever may work the card may schedule and complete its tasks,
# the way they may change its product lines; every change tells the board the new counts.
class Api::V1::Accounts::Kanban::CardTasksController < Api::V1::Accounts::Kanban::BaseController
  before_action :card
  before_action :task, only: [:update, :destroy]

  def index
    render json: { payload: @card.tasks.includes(:user).order(Arel.sql('completed_at IS NOT NULL'), :due_at, :id).map(&:push_event_data) }
  end

  def create
    task = @card.tasks.new(task_params)
    task.user ||= Current.user
    task.save!
    broadcast_updated
    render json: { payload: task.push_event_data }, status: :created
  end

  def update
    @task.update!(task_params)
    broadcast_updated
    render json: { payload: @task.push_event_data }
  end

  def destroy
    @task.destroy!
    broadcast_updated
    head :ok
  end

  private

  def card
    @card = cards_scope.where(board_id: visible_boards.select(:id)).find(params[:card_id])
    authorize @card, :update?
  end

  def task
    @task = @card.tasks.find(params[:id])
  end

  def task_params
    params.permit(:title, :description, :task_type, :due_at, :user_id, :completed)
  end

  def broadcast_updated
    Custom::Kanban::Broadcaster.card_updated(cards_scope.find(@card.id))
  end
end
