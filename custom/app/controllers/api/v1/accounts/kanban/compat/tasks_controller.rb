# The deals in the Pro dialect (operations 8 to 11 of custom/contracts/pro-kanban.md): a Pro "task" is
# a Flow card. `GET kanban/tasks` is this list; the follow-ups that used to be there ("My tasks")
# moved to `kanban/my_tasks`. Everything honours the same visibility and policies as the dashboard.
class Api::V1::Accounts::Kanban::Compat::TasksController < Api::V1::Accounts::Kanban::BaseController
  LIST_LIMIT = 500

  # The card attribute, then the key the dialect calls it and how its value is read.
  UPDATABLE = {
    title: [:title, :keep], description: [:description, :keep], priority: [:priority, :blank_to_nil],
    start_at: [:start_date, :parse_time], due_at: [:due_date, :parse_time],
    custom_attributes: [:custom_attributes, :parse_attributes], labels: [:labels, :parse_labels]
  }.freeze

  # A value in the body that cannot be read; the message is the key of flow_kanban.pro.*.
  class InvalidField < StandardError; end

  before_action :card, only: [:show, :move, :update]

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

  # A partial update: only the keys sent change, and `null` clears a description, a date or the priority. The
  # attributes are assigned whole (the Agents merge theirs before sending) and the labels replace the set.
  def update
    @card.update!(update_attributes)
    updated = cards_in_visible_boards.find(@card.id)
    Custom::Kanban::Broadcaster.card_updated(updated)
    render json: Custom::Kanban::ProSerializer.card(updated)
  rescue InvalidField => e
    render json: { message: I18n.t("flow_kanban.pro.#{e.message}") }, status: :unprocessable_content
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

  def update_source
    params[:task].is_a?(ActionController::Parameters) ? params[:task] : params
  end

  # The attributes to change, from the keys the body really has (a missing key is not a null).
  def update_attributes
    source = update_source
    UPDATABLE.each_with_object({}) do |(attribute, (key, reader)), attrs|
      attrs[attribute] = send(reader, source[key]) if source.key?(key)
    end
  end

  def keep(value)
    value
  end

  def blank_to_nil(value)
    value.presence
  end

  # ISO 8601 (or a plain date); a string that is not one is an error, never a silent clear.
  def parse_time(value)
    return nil if value.blank?

    Time.iso8601(value.to_s)
  rescue ArgumentError
    begin
      Date.iso8601(value.to_s).in_time_zone
    rescue ArgumentError
      raise InvalidField, 'invalid_date'
    end
  end

  def parse_attributes(value)
    return {} if value.nil?
    raise InvalidField, 'invalid_attributes' unless value.is_a?(ActionController::Parameters)

    value.to_unsafe_h
  end

  def parse_labels(value)
    return [] if value.nil?
    raise InvalidField, 'invalid_labels' unless value.is_a?(Array) && value.all?(String)

    value
  end

  def render_problem(key)
    render json: { message: I18n.t("flow_kanban.pro.#{key}") }, status: :unprocessable_content
  end
end
