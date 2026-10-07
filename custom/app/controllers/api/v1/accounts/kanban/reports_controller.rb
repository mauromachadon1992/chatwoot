# A board's funnel report for a period, as unix timestamps the dashboard computes in the
# agent's own time zone. Whoever sees the board sees its report.
class Api::V1::Accounts::Kanban::ReportsController < Api::V1::Accounts::Kanban::BaseController
  MAX_RANGE = 366.days

  def show
    board = find_visible_board(params[:board_id])
    authorize board, :show?
    since, until_time = period

    filters = { board: board, assignee_id: params[:assignee_id].presence }
    report = Custom::Kanban::FunnelReport.new(**filters, since: since, until_time: until_time).call
    report[:forecast] = Custom::Kanban::ForecastReport.new(**filters).call
    report[:lost_reasons] = Custom::Kanban::LostReasonsReport.new(**filters, since: since, until_time: until_time).call
    render json: { payload: report }
  end

  private

  def period
    until_time = params[:until].present? ? Time.zone.at(params[:until].to_i) : Time.current
    since = params[:since].present? ? Time.zone.at(params[:since].to_i) : until_time - 30.days
    since = until_time - MAX_RANGE if until_time - since > MAX_RANGE
    since > until_time ? [until_time, since] : [since, until_time]
  end
end
