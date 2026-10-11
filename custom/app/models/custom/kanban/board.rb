class Custom::Kanban::Board < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :board_inboxes, class_name: 'Custom::Kanban::BoardInbox', dependent: :delete_all
  has_many :inboxes, through: :board_inboxes
  has_many :board_teams, class_name: 'Custom::Kanban::BoardTeam', dependent: :delete_all
  has_many :teams, through: :board_teams
  has_many :board_agents, class_name: 'Custom::Kanban::BoardAgent', dependent: :delete_all
  has_many :agents, through: :board_agents, source: :user
  # Cards first: they reference the stages, so the stages can only go once the cards are gone.
  has_many :cards, class_name: 'Custom::Kanban::Card', dependent: :delete_all
  has_many :stages, -> { order(:position, :id) }, class_name: 'Custom::Kanban::Stage', dependent: :delete_all, inverse_of: :board
  has_many :stage_automations, class_name: 'Custom::Kanban::StageAutomation', dependent: :delete_all, inverse_of: :board

  # The automatic-deal rule (settings.auto_create): a new conversation in one of `inbox_ids`
  # opens a deal on the first open stage, at most `daily_cap` a day. See AutoDealCreator.
  AUTO_CREATE_DEFAULT_CAP = 50
  AUTO_CREATE_CAP_RANGE = (1..500)

  validates :name, presence: true, length: { maximum: 120 }
  validate :restrictions_belong_to_account
  validate :auto_create_is_valid

  scope :ordered, -> { order(:position, :id) }

  # Boards an account member may open. Administrators see every board; an agent sees the
  # unrestricted ones plus those shared with one of their inboxes or teams, or with them by name. This mirrors
  # ConversationPolicy, which grants an agent a conversation through its inbox or team.
  def self.visible_to(user, account)
    boards = where(account: account)
    return boards if account.administrators.exists?(id: user.id)

    boards.where.not(id: restricted_ids(Custom::Kanban::BoardInbox.all, Custom::Kanban::BoardTeam.all, Custom::Kanban::BoardAgent.all))
          .or(boards.where(id: restricted_ids(
            Custom::Kanban::BoardInbox.where(inbox_id: user.inboxes.where(account_id: account.id).select(:id)),
            Custom::Kanban::BoardTeam.where(team_id: user.teams.where(account_id: account.id).select(:id)),
            Custom::Kanban::BoardAgent.where(user_id: user.id)
          )))
  end

  # Ids of the boards named by these inbox, team and agent restriction rows.
  def self.restricted_ids(board_inboxes, board_teams, board_agents)
    where(id: board_inboxes.select(:board_id)).or(where(id: board_teams.select(:board_id)))
                                              .or(where(id: board_agents.select(:board_id))).select(:id)
  end

  def restricted?
    board_inboxes.exists? || board_teams.exists? || board_agents.exists?
  end

  def auto_create
    stored = settings.is_a?(Hash) ? settings.fetch('auto_create', {}) : {}
    {
      'enabled' => stored['enabled'] == true,
      'inbox_ids' => Array(stored['inbox_ids']).map(&:to_i).uniq,
      'daily_cap' => stored.fetch('daily_cap', AUTO_CREATE_DEFAULT_CAP).to_i
    }
  end

  # Takes what the settings panel sends; a key left out keeps its value.
  def auto_create=(values)
    values = values.to_h.stringify_keys.slice('enabled', 'inbox_ids', 'daily_cap')
    current = auto_create
    current['enabled'] = ActiveModel::Type::Boolean.new.cast(values['enabled']) == true if values.key?('enabled')
    current['inbox_ids'] = Array(values['inbox_ids']).compact_blank.map(&:to_i).uniq if values.key?('inbox_ids')
    current['daily_cap'] = Integer(values['daily_cap'], exception: false) || -1 if values.key?('daily_cap')
    self.settings = (settings || {}).merge('auto_create' => current)
  end

  def auto_creates_for?(inbox_id)
    rule = auto_create
    rule['enabled'] && rule['inbox_ids'].include?(inbox_id)
  end

  def auto_created_today
    cards.where(source: 'automatic', created_at: Time.current.all_day).count
  end

  # The rule as the settings panel shows it: with today's count, so the cap reads "12 of 50".
  def auto_create_data
    rule = auto_create
    rule.merge('created_today' => rule['enabled'] ? auto_created_today : 0)
  end

  # Pubsub tokens of everyone allowed to see this board, for realtime updates.
  def member_tokens
    admins = account.administrators.pluck(:pubsub_token)
    agents = if restricted?
               inbox_members = User.joins(:inbox_members).where(inbox_members: { inbox_id: board_inboxes.select(:inbox_id) })
               team_members = User.joins(:team_members).where(team_members: { team_id: board_teams.select(:team_id) })
               inbox_members.pluck(:pubsub_token) + team_members.pluck(:pubsub_token) +
                 User.where(id: board_agents.select(:user_id)).pluck(:pubsub_token)
             else
               account.agents.pluck(:pubsub_token)
             end
    (admins + agents).uniq
  end

  def push_event_data
    {
      id: id,
      name: name,
      description: description,
      position: position,
      inbox_ids: board_inboxes.map(&:inbox_id),
      team_ids: board_teams.map(&:team_id),
      agent_ids: board_agents.map(&:user_id),
      stages: stages.map(&:push_event_data),
      auto_create: auto_create_data
    }
  end

  private

  def restrictions_belong_to_account
    errors.add(:inboxes, :invalid) if inboxes.any? { |inbox| inbox.account_id != account_id }
    errors.add(:teams, :invalid) if teams.any? { |team| team.account_id != account_id }
    errors.add(:agents, :invalid) if agents.any? { |agent| agent.account_users.where(account_id: account_id).none? }
  end

  def auto_create_is_valid
    rule = auto_create
    errors.add(:auto_create, :daily_cap) unless AUTO_CREATE_CAP_RANGE.cover?(rule['daily_cap'])
    return errors.add(:auto_create, :no_inbox) if rule['enabled'] && rule['inbox_ids'].empty?
    return if rule['inbox_ids'].empty?

    known = Inbox.where(account_id: account_id, id: rule['inbox_ids']).count
    errors.add(:auto_create, :inboxes) if known != rule['inbox_ids'].size
  end
end
