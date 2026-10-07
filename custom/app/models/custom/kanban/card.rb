class Custom::Kanban::Card < ApplicationRecord
  include Custom::Kanban::CardHistory
  include Custom::Kanban::CardOutcome

  # Cards are ordered by a float `position`, so a move rewrites one row: the card lands
  # halfway between its new neighbours. Only when two neighbours get closer than MIN_GAP is
  # the whole stage renumbered, which takes ~50 moves into the same slot.
  POSITION_STEP = 1024.0
  MIN_GAP = 1e-6

  belongs_to :account
  belongs_to :board, class_name: 'Custom::Kanban::Board'
  belongs_to :stage, class_name: 'Custom::Kanban::Stage'
  belongs_to :contact
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  # Ceiling for a deal's value: 10 billion in major units, far past any real deal and well
  # inside JavaScript's safe integer range.
  MAX_VALUE_CENTS = 1_000_000_000_000

  has_many :card_conversations, class_name: 'Custom::Kanban::CardConversation', dependent: :delete_all
  has_many :conversations, through: :card_conversations
  has_many :items, -> { order(:position, :id) }, class_name: 'Custom::Kanban::CardItem', dependent: :delete_all,
                                                 inverse_of: :card
  has_many :stage_transitions, class_name: 'Custom::Kanban::StageTransition', dependent: :delete_all
  has_many :tasks, class_name: 'Custom::Kanban::CardTask', dependent: :delete_all, inverse_of: :card

  # Where a deal came from: an agent, or a new conversation (AutoDealCreator). An automatic one
  # `needs_review` until an agent changes it.
  SOURCES = %w[manual automatic].freeze

  validates :title, presence: true, length: { maximum: 255 }
  validates :source, inclusion: { in: SOURCES }
  validates :value_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_VALUE_CENTS }
  validate :stage_belongs_to_board
  validate :contact_belongs_to_account
  validate :assignee_belongs_to_account
  validate :value_follows_items, if: :value_cents_changed?

  before_validation :inherit_from_stage
  before_save :touch_stage_changed_at, if: :stage_id_changed?
  before_create :place_on_top
  after_create :record_stage_entry
  before_update :mark_reviewed, if: :reviewed_by_agent?
  after_update :record_stage_entry, if: :saved_change_to_stage_id?
  after_save :notify_assignee, if: :saved_change_to_assignee_id?

  scope :ordered, -> { order(:position, :id) }

  # Deals past their stage's limit (stages.stale_after_days): open stages only, counted from
  # when the deal entered the stage. The stalled-deal job and the board filter both read it.
  scope :stale, lambda { |now = Time.current|
    joins(:stage)
      .where(flow_kanban_stages: { stage_type: Custom::Kanban::Stage.stage_types[:open] })
      .where.not(flow_kanban_stages: { stale_after_days: nil })
      .where('COALESCE(flow_kanban_cards.stage_changed_at, flow_kanban_cards.created_at) <= ' \
             'CAST(:now AS timestamp) - make_interval(days => flow_kanban_stages.stale_after_days)', now: now)
  }

  # Whole days past the stage's limit started counting, or nil when the deal is not stalled.
  def stale_days(now = Time.current)
    return unless stage&.stage_type_open? && stage.stale_after_days

    days = ((now - (stage_changed_at || created_at)) / 1.day).floor
    days if days >= stage.stale_after_days
  end

  # Moves the card to `stage`, between the cards the dashboard showed around the drop point.
  # Either neighbour may be nil (top or bottom of the column, or an empty column). `attributes`
  # are saved with the move, inside the lock (why a deal was lost, when it lands on a lost stage).
  def move_to!(stage:, previous_card_id: nil, next_card_id: nil, attributes: {})
    with_lock do
      assign_attributes(attributes)
      siblings = stage.cards.where.not(id: id)
      previous_card = previous_card_id.present? ? siblings.find(previous_card_id) : nil
      next_card = next_card_id.present? ? siblings.find(next_card_id) : nil

      if previous_card && next_card && (next_card.position - previous_card.position).abs < MIN_GAP
        self.class.renumber!(stage, except: self)
        previous_card.reload
        next_card.reload
      end

      self.stage = stage
      self.position = position_between(previous_card, next_card, siblings)
      save!
    end
  end

  def self.renumber!(stage, except: nil)
    # Positions only: nothing to validate, and per-row callbacks would broadcast every card.
    stage.cards.where.not(id: except&.id).ordered.pluck(:id).each_with_index do |card_id, index|
      where(id: card_id).update_all(position: index * POSITION_STEP) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # A deal with products is worth their sum; one without keeps the value an agent typed (or,
  # once its last product is removed, the last sum, which the agent may then change).
  def recalculate_value!
    return if items_count.zero?

    @recalculating_value = true
    update!(value_cents: items.reload.sum(&:total_cents))
  ensure
    @recalculating_value = false
  end

  # Conversations go out by `display_id` only: that is how the dashboard routes and stores
  # them, and sending the internal id next to it is how cards got matched to the wrong
  # conversation in Pro (see AGENTS.md, "Conversation ids").
  # The board gets the value and the item count; the lines go only to whoever opens the card.
  def push_event_data(with_items: false)
    data = {
      id: id,
      board_id: board_id,
      stage_id: stage_id,
      title: title,
      description: description,
      position: position,
      value_cents: value_cents,
      items_count: items_count,
      tasks: task_summary,
      **state_data,
      created_by_id: created_by_id,
      **timestamps_data,
      contact: contact_data,
      assignee: assignee&.push_event_data,
      conversations: card_conversations.map { |link| conversation_data(link.conversation) }
    }
    with_items ? data.merge(items: items.map(&:push_event_data)) : data
  end

  private

  def position_between(previous_card, next_card, siblings)
    return (previous_card.position + next_card.position) / 2 if previous_card && next_card
    return previous_card.position + POSITION_STEP if previous_card
    return next_card.position - POSITION_STEP if next_card

    (siblings.minimum(:position) || POSITION_STEP) - POSITION_STEP
  end

  def state_data
    { source: source, needs_review: needs_review, stale_days: stale_days, expected_close_on: expected_close_on&.iso8601,
      lost_reason: lost_reason&.push_event_data, lost_note: lost_note }
  end

  def timestamps_data
    { stage_changed_at: stage_changed_at&.to_i, created_at: created_at.to_i, updated_at: updated_at.to_i }
  end

  # What the board shows about the follow-ups; the tasks themselves go only to whoever opens the card.
  def task_summary
    open_tasks = tasks.reject(&:completed?)
    { open: open_tasks.size, overdue: open_tasks.count(&:overdue?), next_due_at: open_tasks.map(&:due_at).min&.to_i }
  end

  def contact_data
    {
      id: contact.id,
      name: contact.name,
      email: contact.email,
      phone_number: contact.phone_number,
      thumbnail: contact.avatar_url
    }
  end

  def conversation_data(conversation)
    {
      display_id: conversation.display_id,
      inbox_id: conversation.inbox_id,
      status: conversation.status,
      last_activity_at: conversation.last_activity_at&.to_i
    }
  end

  def inherit_from_stage
    self.board_id ||= stage&.board_id
    self.account_id ||= board&.account_id
  end

  def place_on_top
    return if position_changed? && position.present?

    self.position = (stage.cards.minimum(:position) || POSITION_STEP) - POSITION_STEP
  end

  # A move starts a new stay: the stall clock and its one notification start over.
  def touch_stage_changed_at
    self.stage_changed_at = Time.current
    self.stale_notified_at = nil
  end

  # Positions and the alert stamp are the system's; anything else an agent changes on an
  # automatic deal means they have looked at it.
  SYSTEM_COLUMNS = %w[position updated_at stale_notified_at needs_review].freeze

  def reviewed_by_agent?
    needs_review? && Current.user.present? && (changed - SYSTEM_COLUMNS).any?
  end

  def mark_reviewed
    self.needs_review = false
  end

  # Whoever is handed the deal is told, unless they handed it to themselves.
  def notify_assignee
    Custom::Kanban::Notifier.card_assigned(self, actor: Current.user)
  end

  def record_stage_entry
    stage_transitions.create!(
      account_id: account_id, board_id: board_id, to_stage_id: stage_id,
      from_stage_id: saved_changes['stage_id']&.first, user: Current.user, created_at: stage_changed_at || Time.current
    )
  end

  def value_follows_items
    errors.add(:value_cents, :follows_items) if items_count.positive? && !@recalculating_value
  end

  def stage_belongs_to_board
    errors.add(:stage, :invalid) if stage && stage.board_id != board_id
  end

  def contact_belongs_to_account
    errors.add(:contact, :invalid) if contact && contact.account_id != account_id
  end

  def assignee_belongs_to_account
    return if assignee.blank?

    errors.add(:assignee, :invalid) unless account.users.exists?(id: assignee_id)
  end
end
