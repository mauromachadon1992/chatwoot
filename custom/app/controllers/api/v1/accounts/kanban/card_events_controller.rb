# A deal's history, newest first, a page at a time. Whoever may open the card may read it.
class Api::V1::Accounts::Kanban::CardEventsController < Api::V1::Accounts::Kanban::BaseController
  PER_PAGE = 20

  def index
    card = Custom::Kanban::Card.where(board_id: visible_boards.select(:id)).find(params[:card_id])
    authorize card, :show?
    page = [params[:page].to_i, 1].max
    events = card.events.newest_first.includes(:user).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    render json: { payload: events.first(PER_PAGE).map(&:push_event_data), meta: { page: page, has_more: events.size > PER_PAGE } }
  end
end
