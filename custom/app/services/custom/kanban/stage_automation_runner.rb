# Applies a board's stage automations to the cards linked to a conversation. Called by the
# conversation listener, never by a card move, so a rule cannot trigger itself.
#
# One rule per card per event: the oldest matching one wins. A card already in the target
# stage is left alone, and a card an agent dragged elsewhere stays there until the conversation
# changes again.
class Custom::Kanban::StageAutomationRunner
  def self.status_changed(conversation)
    new(conversation).run { |rule| rule.matches_status?(conversation.status) }
  end

  # `changes` is the conversation's previous_changes: a label is "added" when it is in the new
  # cached label list and was not in the old one.
  def self.labels_changed(conversation, changes)
    old_list, new_list = Array(changes.with_indifferent_access[:cached_label_list]).map { |list| list.to_s.split(',').map(&:strip) }
    return if new_list.nil?

    added = new_list - old_list.to_a
    new(conversation).run { |rule| added.any? { |label| rule.matches_label?(label) } }
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def run(&)
    cards.find_each do |card|
      rule = rules_for(card).find(&)
      next if rule.nil? || rule.stage_id == card.stage_id

      card.move_to!(stage: rule.stage)
      Custom::Kanban::Broadcaster.card_updated(card)
    rescue StandardError => e
      # One broken card must not stop the others, nor the rest of the conversation's listeners.
      ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    end
  end

  private

  def cards
    card_ids = Custom::Kanban::CardConversation.where(conversation_id: @conversation.id).select(:card_id)
    Custom::Kanban::Card.where(id: card_ids, account_id: @conversation.account_id)
                        .includes(:board, :assignee, :tasks, card_conversations: :conversation, contact: { avatar_attachment: :blob })
  end

  def rules_for(card)
    @rules ||= Custom::Kanban::StageAutomation.active.where(board_id: cards.select(:board_id)).includes(:stage).ordered.group_by(&:board_id)
    @rules.fetch(card.board_id, [])
  end
end
