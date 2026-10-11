# One step of a rule: move the deal, create a task on it, assign it, or label its conversations.
# It knows how to normalise what a client sent, say what is wrong with it, say what it points at
# that no longer exists, and run itself. A rule with a missing target is never run half way
# (StageAutomation#needs_attention), so `execute` can assume its targets exist and still checks
# the things only the moment can tell (the deal's agent, who may see the board).
class Custom::Kanban::AutomationAction
  TYPES = %w[move_to_stage create_task assign_agent add_label].freeze
  KEYS = {
    'move_to_stage' => %w[stage_id],
    'create_task' => %w[title task_type due_in_hours assignee],
    'assign_agent' => %w[user_id],
    'add_label' => %w[label]
  }.freeze
  DEAL_AGENT = 'deal_agent'.freeze
  DUE_HOURS = (0..720)
  LABEL_MAX_LENGTH = 100

  attr_reader :type, :config

  # What a client sent, cleaned: unknown types and keys dropped, numbers as numbers, text squished.
  def self.normalize(raw)
    Array(raw).filter_map do |item|
      item = item.to_h.stringify_keys
      next unless TYPES.include?(item['type'])

      new(item['type'], item.slice(*KEYS.fetch(item['type'])))
    end.map(&:to_h)
  end

  def self.parse(list)
    Array(list).filter_map { |item| new(item['type'], item.except('type')) if item.is_a?(Hash) && TYPES.include?(item['type']) }
  end

  def initialize(type, config)
    @type = type
    @config = clean(config)
  end

  def to_h
    { 'type' => type }.merge(config)
  end

  # Why this step cannot be saved, as keys the model turns into messages.
  def errors(automation)
    TYPES.include?(type) ? send(:"#{type}_errors", automation) : [:type]
  end

  # What it points at that was deleted since: the rule shows them and does not run.
  def missing(automation)
    TYPES.include?(type) ? send(:"#{type}_missing", automation) : []
  end

  # Runs on `card`; answers { 'type' =>, 'status' => 'done'|'skipped', ... } for the deal's history.
  def execute(card, automation)
    send(:"run_#{type}", card, automation)
  end

  private

  def clean(config)
    config = config.to_h.stringify_keys
    config['stage_id'] = Integer(config['stage_id'], exception: false) if config.key?('stage_id')
    config['user_id'] = Integer(config['user_id'], exception: false) if config.key?('user_id')
    config['due_in_hours'] = Integer(config['due_in_hours'], exception: false) if config.key?('due_in_hours')
    %w[title label].each { |key| config[key] = config[key].to_s.squish if config.key?(key) }
    config['assignee'] = normalise_assignee(config['assignee']) if config.key?('assignee')
    config
  end

  def normalise_assignee(value)
    value.to_s == DEAL_AGENT ? DEAL_AGENT : Integer(value, exception: false)
  end

  def fixed_assignee?
    config['assignee'] != DEAL_AGENT
  end

  def stage_in(automation)
    automation.board.stages.find_by(id: config['stage_id'])
  end

  def member(automation, id = config['user_id'])
    automation.account.users.find_by(id: id) if id
  end

  def label_exists?(automation)
    config['label'].present? && config['label'].length <= LABEL_MAX_LENGTH && automation.account.labels.exists?(title: config['label'])
  end

  def move_to_stage_errors(automation)
    stage_in(automation) ? [] : [:stage]
  end

  def assign_agent_errors(automation)
    member(automation) ? [] : [:agent]
  end

  def add_label_errors(automation)
    label_exists?(automation) ? [] : [:label]
  end

  def create_task_errors(automation)
    errors = []
    errors << :title unless config['title'].present? && config['title'].length <= 255
    errors << :task_type unless Custom::Kanban::CardTask::TASK_TYPES.include?(config['task_type'])
    errors << :due unless DUE_HOURS.cover?(config['due_in_hours'])
    errors << :agent unless config['assignee'] == DEAL_AGENT || member(automation, config['assignee'])
    errors
  end

  def move_to_stage_missing(automation)
    stage_in(automation) ? [] : ['stage_missing']
  end

  def assign_agent_missing(automation)
    member(automation) ? [] : ['agent_missing']
  end

  def add_label_missing(automation)
    label_exists?(automation) ? [] : ['label_missing']
  end

  def create_task_missing(automation)
    fixed_assignee? && !member(automation, config['assignee']) ? ['agent_missing'] : []
  end

  # --- running ---------------------------------------------------------------------------

  def run_move_to_stage(card, automation)
    stage = stage_in(automation)
    return skipped('already_there') if card.stage_id == stage.id

    card.move_to!(stage: stage)
    # Nobody dragged it: the agent of the deal would not otherwise know it moved.
    Custom::Kanban::Notifier.card_moved(card, stage)
    done(stage_name: stage.name)
  end

  def run_create_task(card, automation)
    user = config['assignee'] == DEAL_AGENT ? card.assignee : member(automation, config['assignee'])
    return skipped('no_agent') if user.nil?
    return skipped('agent_cannot_see_board') unless sees_board?(user, card)

    Custom::Kanban::CardTask.create!(card: card, user: user, title: config['title'], task_type: config['task_type'],
                                     due_at: Time.current + config['due_in_hours'].hours)
    done(title: config['title'], agent_name: user.name)
  end

  def run_assign_agent(card, automation)
    user = member(automation)
    return skipped('already_assigned') if card.assignee_id == user.id
    return skipped('agent_cannot_see_board') unless sees_board?(user, card)

    card.update!(assignee: user)
    done(agent_name: user.name)
  end

  def run_add_label(card, _automation)
    pending = card.conversations.reject { |conversation| conversation.label_list.include?(config['label']) }
    return skipped(card.conversations.empty? ? 'no_conversation' : 'already_labelled') if pending.empty?

    pending.each { |conversation| conversation.add_labels([config['label']]) }
    done(label: config['label'])
  end

  def sees_board?(user, card)
    Custom::Kanban::Board.visible_to(user, card.account).exists?(id: card.board_id)
  end

  def done(extra = {})
    { 'type' => type, 'status' => 'done' }.merge(extra.stringify_keys)
  end

  def skipped(reason)
    { 'type' => type, 'status' => 'skipped', 'reason' => reason }
  end
end
