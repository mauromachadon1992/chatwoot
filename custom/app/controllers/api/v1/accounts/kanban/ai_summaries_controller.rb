# An AI summary of a deal, drafted on request (see Custom::Kanban::DealSummaryService). Nothing
# is written to the deal: the dashboard shows the draft and the agent accepts, edits or discards
# it, then tells the server which (`decide`), which is all the metric needs.
class Api::V1::Accounts::Kanban::AiSummariesController < Api::V1::Accounts::Kanban::BaseController
  before_action :require_feature
  before_action :card, only: [:create]

  def create
    wait = Custom::Kanban::AiDraft.wait_minutes(Current.user)
    return render_error(:rate_limited, :too_many_requests, minutes: wait) if wait

    draft = Custom::Kanban::AiDraft.create!(account: Current.account, card: @card, user: Current.user)
    result = Custom::Kanban::DealSummaryService.new(account: Current.account, card: @card, user: Current.user).perform
    return fail_draft(draft, result) if result[:error] || result[:message].blank?

    draft.update!(status: 'generated', used: result[:used], model: result.dig(:usage, 'model'))
    render json: { payload: { draft_id: draft.id, summary: result[:message], next_task: result[:task], used: result[:used] } }
  end

  # The agent's answer to a draft: only the first one counts.
  def decide
    draft = Custom::Kanban::AiDraft.where(account: Current.account, user: Current.user).find(params[:id])
    decision = params.require(:decision)
    return head(:unprocessable_entity) unless Custom::Kanban::AiDraft::DECISIONS.include?(decision)

    draft.decide!(decision)
    head :ok
  end

  private

  def require_feature
    on = Custom::Kanban::Features.enabled?(Current.account, :ai_summary) && Current.account.feature_enabled?('captain_tasks')
    render_error(:disabled, :forbidden) unless on
  end

  def card
    @card = Custom::Kanban::Card.where(board_id: visible_boards.select(:id)).find(params[:card_id])
    authorize @card, :update?
  end

  # What went wrong, in words an agent can act on; the technical detail stays in the log.
  def fail_draft(draft, result)
    draft.update!(status: 'failed')
    code = result[:error_code]
    Rails.logger.warn("[KANBAN][AI] deal #{@card.id}: #{code} #{result[:error]}") unless code == 422
    case code
    when 422 then render_error(:nothing_to_summarize, :unprocessable_entity)
    when 401 then render_error(:not_configured, :service_unavailable)
    when 403 then render_error(:disabled, :forbidden)
    when 429 then render_error(:quota, :too_many_requests)
    else render_error(:failed, :bad_gateway)
    end
  end

  def render_error(key, status, **)
    render json: { error: I18n.t("flow_kanban.ai.#{key}", **), code: key }, status: status
  end
end
