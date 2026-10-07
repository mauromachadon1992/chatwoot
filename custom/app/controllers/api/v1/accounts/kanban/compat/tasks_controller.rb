# The deals in the Pro dialect (operations 8 to 11 of custom/contracts/pro-kanban.md): a Pro "task" is
# a Flow card. `GET kanban/tasks` is this list; the follow-ups that used to be there ("My tasks")
# moved to `kanban/my_tasks`. Everything honours the same visibility and policies as the dashboard.
class Api::V1::Accounts::Kanban::Compat::TasksController < Api::V1::Accounts::Kanban::BaseController
  LIST_LIMIT = 500

  before_action :card, only: [:show, :move]

  def index
    cards = cards_in_visible_boards
    cards = cards.where(board_id: params[:board_id]) if params[:board_id].present?
    total = cards.count
    listed = cards.joins(:stage).reorder('flow_kanban_cards.board_id, flow_kanban_stages.position, flow_kanban_cards.position, flow_kanban_cards.id')
    render json: { payload: listed.limit(LIST_LIMIT).map { |card| Custom::Kanban::ProSerializer.card(card) },
                   meta: { total: total, truncated: total > LIST_LIMIT } }
  end

  # The bare card, no envelope: that is the shape the Agents' client reads.
  def show
    render json: Custom::Kanban::ProSerializer.card(@card)
  end

  # A card needs a contact: it comes from the conversation (by display id) or from `contact_id`. Without
  # a step the first open one is used.
  def create
    board = find_visible_board(task_params[:board_id])
    conversation = find_conversation
    contact = conversation&.contact || Current.account.contacts.find_by(id: task_params[:contact_id])
    return render_problem(:contact_needed) unless contact

    card = build_card(board, contact)
    authorize card
    ActiveRecord::Base.transaction do
      card.save!
      card.card_conversations.create!(conversation: conversation) if conversation
    end
    saved = cards_in_visible_boards.find(card.id)
    Custom::Kanban::Broadcaster.card_created(saved)
    render json: Custom::Kanban::ProSerializer.card(saved)
  end

  # `board_step_id` is the target; `insert_before_task_id` the card it lands above (a card of that step).
  def move
    stage = @card.board.stages.find(params.require(:board_step_id))
    previous_id, next_id = neighbours(stage)
    @card.move_to!(stage: stage, previous_card_id: previous_id, next_card_id: next_id, attributes: lost_attributes(stage))
    moved = cards_in_visible_boards.find(@card.id)
    Custom::Kanban::Broadcaster.card_updated(moved)
    render json: Custom::Kanban::ProSerializer.card(moved)
  end

  private

  # [previous, next] ids for "directly above `insert_before_task_id`"; a card that is not on the target step is a 404.
  def neighbours(stage)
    return [nil, nil] if params[:insert_before_task_id].blank?

    siblings = stage.cards.where.not(id: @card.id)
    below = siblings.find(params[:insert_before_task_id])
    above = siblings.where('position < ?', below.position).order(position: :desc, id: :desc).first
    [above&.id, below.id]
  end

  def cards_in_visible_boards
    Custom::Kanban::ProSerializer.preloaded.where(board_id: visible_boards.select(:id))
  end

  def card
    @card = cards_in_visible_boards.find(params[:id])
    authorize @card
  end

  # `{task: {...}}` is the root key the client sends; a flat body works too.
  def task_params
    @task_params ||= begin
      source = params[:task].is_a?(ActionController::Parameters) ? params[:task] : params
      source.permit(:title, :description, :board_id, :board_step_id, :conversation_id, :contact_id, :assignee_id, :value, :value_cents)
    end
  end

  def build_card(board, contact)
    stage = step_for(board)
    card = stage.cards.new(board: board, contact: contact, created_by: Current.user, description: task_params[:description],
                           assignee_id: task_params[:assignee_id], value_cents: value_cents)
    card.title = task_params[:title].presence || contact.name.presence || contact.phone_number || contact.email
    card
  end

  def step_for(board)
    return board.stages.find(task_params[:board_step_id]) if task_params[:board_step_id].present?

    board.stages.stage_type_open.order(:position, :id).first || board.stages.order(:position, :id).first!
  end

  # A number in the account's currency (`value`) or integer cents; money never goes through a float.
  def value_cents
    return task_params[:value_cents].to_i if task_params[:value_cents].present?
    return 0 if task_params[:value].blank?

    (BigDecimal(task_params[:value].to_s) * 100).round.to_i
  rescue ArgumentError
    raise(ActiveRecord::RecordInvalid, Custom::Kanban::Card.new.tap { |card| card.errors.add(:value_cents, :invalid) })
  end

  def find_conversation
    return if task_params[:conversation_id].blank?

    conversation = Current.account.conversations.find_by!(display_id: task_params[:conversation_id])
    authorize conversation, :show?
    conversation
  end

  def lost_attributes(stage)
    return {} unless stage.stage_type_lost?

    reason = Custom::Kanban::LostReason.where(account: Current.account).find(params[:lost_reason_id]) if params[:lost_reason_id].present?
    { lost_reason: reason, lost_note: params[:lost_note].presence }
  end

  def render_problem(key)
    render json: { message: I18n.t("flow_kanban.pro.#{key}") }, status: :unprocessable_content
  end
end
