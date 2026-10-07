# Opens a deal when a new conversation arrives, on every board whose automatic-deal rule covers
# its inbox (Board#auto_create). Off unless a super admin enabled the feature for the account and
# an administrator switched the rule on for the board.
#
# Guards, in order: the account feature; individual conversations only (a group chat is not a
# customer); a contact who already has an open deal on that board gets none; the board's daily
# cap. The contact row is locked while deciding, so two conversations of the same contact arriving
# together still open one deal, and a retried job finds the deal it made and stops.
class Custom::Kanban::AutoDealCreator
  def self.perform(conversation)
    new(conversation).perform
  end

  def initialize(conversation)
    @conversation = conversation
    @account = conversation&.account
  end

  def perform
    return [] unless eligible?

    boards.filter_map do |board|
      card = create_on(board)
      Custom::Kanban::Broadcaster.card_created(card) if card
      card
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: @account).capture_exception
      nil
    end
  end

  private

  def eligible?
    @conversation.present? && @conversation.contact.present? && !@conversation.group_type_group? &&
      Custom::Kanban::Features.enabled?(@account, :auto_create)
  end

  def boards
    Custom::Kanban::Board.where(account: @account).ordered.select { |board| board.auto_creates_for?(@conversation.inbox_id) }
  end

  def create_on(board)
    contact = @conversation.contact
    contact.with_lock do
      next if open_deal?(board, contact)
      next if board.auto_created_today >= board.auto_create['daily_cap']

      stage = board.stages.stage_type_open.first
      next unless stage

      build_card(board, stage, contact)
    end
  end

  def open_deal?(board, contact)
    board.cards.joins(:stage).exists?(contact: contact, flow_kanban_stages: { stage_type: Custom::Kanban::Stage.stage_types[:open] })
  end

  def build_card(board, stage, contact)
    card = board.cards.create!(
      stage: stage, contact: contact, source: 'automatic', needs_review: true,
      title: contact.name.presence || contact.phone_number.presence || contact.email.presence || "##{@conversation.display_id}",
      assignee: assignee
    )
    card.card_conversations.create!(conversation: @conversation)
    Custom::Kanban::Card.includes(:assignee, :tasks, :stage, card_conversations: :conversation, contact: { avatar_attachment: :blob })
                        .find(card.id)
  end

  # The conversation's agent, when they belong to the account; otherwise the deal waits unassigned.
  def assignee
    agent = @conversation.assignee
    agent if agent && @account.users.exists?(id: agent.id)
  end
end
