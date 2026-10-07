# Applies a board's rules to the deals an event is about, each rule at most once per trigger
# episode (a status reached, a label added, a deal created, a stall, the last message of a
# conversation). Called from the conversation listener, the stalled-deal job, the no-reply job and
# a new deal; never from a card move, so a rule cannot trigger itself.
#
# Several rules may match one event: they run in the order they were made, so when two of them
# move the deal the later one wins. A rule that points at something deleted does not run (see
# StageAutomation#needs_attention), and a rule stops for the day at RUNS_PER_DAY.
class Custom::Kanban::AutomationRunner
  class << self
    def status_changed(conversation)
      episode = "status:#{conversation.id}:#{conversation.status}:#{conversation.status_changed_at.to_i}"
      new.run('conversation_status_changed', linked_cards(conversation), ->(_card) { episode }) do |rule, _card|
        rule.matches_status?(conversation.status)
      end
    end

    # `changes` is the conversation's previous_changes: a label is "added" when it is in the new
    # cached label list and was not in the old one.
    def labels_changed(conversation, changes)
      old_list, new_list = Array(changes.with_indifferent_access[:cached_label_list]).map { |list| list.to_s.split(',').map(&:strip) }
      return if new_list.nil?

      added = new_list - old_list.to_a
      stamp = conversation.updated_at.to_i
      new.run('label_added', linked_cards(conversation), ->(_card) { "label:#{conversation.id}:#{stamp}" }) do |rule, _card|
        added.any? { |label| rule.matches_label?(label) }
      end
    end

    def deal_created(card)
      new.run('deal_created', [card], ->(deal) { "created:#{deal.id}" })
    end

    # A stall is one stay in the stage: moving the deal and stalling again is a new episode.
    def deal_stalled(card)
      new.run('deal_stalled', [card], ->(deal) { "stalled:#{deal.id}:#{deal.stage_changed_at.to_i}" })
    end

    # `last_message` is what the conversation ended on; the episode ends with the next message.
    def no_reply(card, conversation_id, last_message, now: Time.current)
      elapsed = (now - last_message[:created_at]) / 1.hour
      customer_silent = last_message[:message_type] != Message.message_types[:incoming]
      new.run('no_reply', [card], ->(_deal) { "noreply:#{conversation_id}:#{last_message[:id]}" }) do |rule, _deal|
        config = rule.trigger_config
        elapsed >= config['hours'] && (config['side'] == 'customer') == customer_silent
      end
    end

    private

    def linked_cards(conversation)
      card_ids = Custom::Kanban::CardConversation.where(conversation_id: conversation.id).select(:card_id)
      Custom::Kanban::Card.preloaded.where(id: card_ids, account_id: conversation.account_id).to_a
    end
  end

  def run(trigger, cards, episode, &match)
    rules = Custom::Kanban::StageAutomation.active.where(trigger_type: trigger, board_id: cards.map(&:board_id).uniq).ordered
                                           .group_by(&:board_id)
    cards.each do |card|
      rules.fetch(card.board_id, []).each do |rule|
        apply(rule, card, episode.call(card)) if rule.runnable? && matches?(match, rule, card)
      end
    end
  end

  private

  # A rule with no further condition (the trigger alone) matches every time.
  def matches?(match, rule, card)
    match.nil? || match.call(rule, card)
  end

  def apply(rule, card, episode_key)
    return if rule.runs_today >= Custom::Kanban::StageAutomation::RUNS_PER_DAY
    return unless Custom::Kanban::AutomationRun.claim(rule, card, episode_key)

    results = rule.steps.map { |step| execute(step, card, rule) }
    Custom::Kanban::CardEvent.record!(card, 'automation_ran', { automation_id: rule.id, trigger: rule.trigger_type, results: results },
                                      user: nil)
    Custom::Kanban::Broadcaster.card_updated(Custom::Kanban::Card.preloaded.find(card.id))
  rescue StandardError => e
    # One broken rule or deal must not stop the others, nor the rest of the event's listeners.
    ChatwootExceptionTracker.new(e, account: card.account).capture_exception
  end

  # A step that raises is recorded as failed and the next one still runs: the deal's history
  # says what happened, and the rest of the rule is not lost to one bad step.
  def execute(step, card, rule)
    card.reload
    step.execute(card, rule)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: card.account).capture_exception
    { 'type' => step.type, 'status' => 'failed' }
  end
end
