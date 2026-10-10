# Fires the "no reply for N hours" rules, which no event announces: the silence is what is looked
# for. Every 15 minutes, for each board that has such a rule, it takes the deals in open stages
# with an open linked conversation, reads what each conversation last said (a message anyone could
# read: not an activity line, not a private note) and hands it to the runner, which acts once per
# last message. A conversation silent for more than STALE_AFTER is left alone: that is history.
class Custom::Kanban::NoReplyAutomationsJob < ApplicationJob
  queue_as :scheduled_jobs

  BATCH = 500
  STALE_AFTER = 30.days

  def perform
    now = Time.current
    board_ids = Custom::Kanban::StageAutomation.active.where(trigger_type: 'no_reply').distinct.pluck(:board_id)
    board_ids.each { |board_id| process(board_id, now) }
  end

  private

  def process(board_id, now)
    links = open_links(board_id)
    return if links.empty?

    last = last_messages(links.map(&:last), now)
    cards = Custom::Kanban::Card.preloaded.where(id: links.map(&:first)).index_by(&:id)
    links.each do |card_id, conversation_id|
      message = last[conversation_id]
      Custom::Kanban::AutomationRunner.no_reply(cards[card_id], conversation_id, message, now: now) if message && cards[card_id]
    end
  end

  # [[card_id, conversation_id], ...] of deals in open stages with an open conversation.
  def open_links(board_id)
    Custom::Kanban::CardConversation.joins(:conversation, card: :stage)
                                    .where(board_id: board_id, flow_kanban_stages: { stage_type: Custom::Kanban::Stage.stage_types[:open] },
                                           conversations: { status: Conversation.statuses[:open] })
                                    .order(:card_id).limit(BATCH).pluck(:card_id, :conversation_id)
  end

  # conversation_id => { id:, message_type:, created_at: } of its last message anyone could read.
  def last_messages(conversation_ids, now)
    Message.chat.where(conversation_id: conversation_ids).where.not(message_type: :template)
           .select('DISTINCT ON (conversation_id) conversation_id, id, message_type, created_at')
           .reorder('conversation_id, created_at DESC, id DESC')
           .each_with_object({}) do |message, by_conversation|
             next if message.created_at < now - STALE_AFTER

             by_conversation[message.conversation_id] =
               { id: message.id, message_type: Message.message_types[message.message_type], created_at: message.created_at }
           end
  end
end
