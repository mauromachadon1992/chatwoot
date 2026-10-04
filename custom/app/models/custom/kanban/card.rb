class Custom::Kanban::Card < ApplicationRecord
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

  has_many :card_conversations, class_name: 'Custom::Kanban::CardConversation', dependent: :delete_all
  has_many :conversations, through: :card_conversations

  validates :title, presence: true, length: { maximum: 255 }
  validate :stage_belongs_to_board
  validate :contact_belongs_to_account
  validate :assignee_belongs_to_account

  before_validation :inherit_from_stage
  before_save :touch_stage_changed_at, if: :stage_id_changed?
  before_create :place_on_top

  scope :ordered, -> { order(:position, :id) }

  # Moves the card to `stage`, between the cards the dashboard showed around the drop point.
  # Either neighbour may be nil (top or bottom of the column, or an empty column).
  def move_to!(stage:, previous_card_id: nil, next_card_id: nil)
    with_lock do
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

  # Conversations go out by `display_id` only: that is how the dashboard routes and stores
  # them, and sending the internal id next to it is how cards got matched to the wrong
  # conversation in Pro (see AGENTS.md, "Conversation ids").
  def push_event_data
    {
      id: id,
      board_id: board_id,
      stage_id: stage_id,
      title: title,
      description: description,
      position: position,
      created_by_id: created_by_id,
      stage_changed_at: stage_changed_at&.to_i,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i,
      contact: contact_data,
      assignee: assignee&.push_event_data,
      conversations: card_conversations.map { |link| conversation_data(link.conversation) }
    }
  end

  private

  def position_between(previous_card, next_card, siblings)
    return (previous_card.position + next_card.position) / 2 if previous_card && next_card
    return previous_card.position + POSITION_STEP if previous_card
    return next_card.position - POSITION_STEP if next_card

    (siblings.minimum(:position) || POSITION_STEP) - POSITION_STEP
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

  def touch_stage_changed_at
    self.stage_changed_at = Time.current
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
