# My tasks: the follow-ups of every deal the agent can see, in one list. An agent gets their
# own; an administrator may also ask for everyone's (`scope=all`).
#
#   GET kanban/my_tasks?scope=mine|all&status=open|done&board_id=&page=&today_ends_at=&count_only=
#
# Open tasks come by due date, done ones (the last 7 days) most recent first. Grouping into
# overdue, today and upcoming is the dashboard's, in the viewer's own time zone; `today_ends_at`
# (the end of the viewer's day, ISO 8601) lets the server count today's for the tab badge.
class Api::V1::Accounts::Kanban::MyTasksController < Api::V1::Accounts::Kanban::BaseController
  PER_PAGE = 100
  DONE_WINDOW = 7.days

  def index
    tasks = scoped_tasks
    meta = counts(tasks)
    return render json: { meta: meta } if ActiveModel::Type::Boolean.new.cast(params[:count_only])

    page = [params[:page].to_i, 1].max
    listed = status_filtered(tasks).includes(:user, card: :board).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    render json: {
      payload: listed.first(PER_PAGE).map { |task| row(task) },
      meta: meta.merge(page: page, has_more: listed.size > PER_PAGE)
    }
  end

  private

  def scoped_tasks
    tasks = Custom::Kanban::CardTask.where(account: Current.account, card_id: visible_cards)
    tasks = tasks.where(card_id: Custom::Kanban::Card.where(board_id: params[:board_id]).select(:id)) if params[:board_id].present?
    everyone? ? tasks : tasks.where(user: Current.user)
  end

  def everyone?
    return false unless params[:scope] == 'all'
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?

    true
  end

  def visible_cards
    Custom::Kanban::Card.where(board_id: visible_boards.select(:id)).select(:id)
  end

  def status_filtered(tasks)
    if params[:status] == 'done'
      tasks.where(completed_at: (Time.current - DONE_WINDOW)..).order(completed_at: :desc, id: :desc)
    else
      tasks.open_tasks.order(:due_at, :id)
    end
  end

  def counts(tasks)
    open = tasks.open_tasks
    now = Time.current
    {
      open_count: open.count,
      overdue_count: open.where(due_at: ...now).count,
      due_today_count: today_ends_at ? open.where(due_at: now..today_ends_at).count : nil
    }
  end

  def today_ends_at
    return @today_ends_at if defined?(@today_ends_at)

    @today_ends_at = begin
      value = Time.zone.parse(params[:today_ends_at].to_s)
      value if value&.between?(Time.current, 2.days.from_now)
    rescue ArgumentError
      nil
    end
  end

  def row(task)
    card = task.card
    task.push_event_data.merge(card: { id: card.id, title: card.title, board_id: card.board_id, board_name: card.board.name })
  end
end
