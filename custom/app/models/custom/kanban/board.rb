class Custom::Kanban::Board < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :board_inboxes, class_name: 'Custom::Kanban::BoardInbox', dependent: :delete_all
  has_many :inboxes, through: :board_inboxes
  has_many :board_teams, class_name: 'Custom::Kanban::BoardTeam', dependent: :delete_all
  has_many :teams, through: :board_teams
  # Cards first: they reference the stages, so the stages can only go once the cards are gone.
  has_many :cards, class_name: 'Custom::Kanban::Card', dependent: :delete_all
  has_many :stages, -> { order(:position, :id) }, class_name: 'Custom::Kanban::Stage', dependent: :delete_all, inverse_of: :board

  validates :name, presence: true, length: { maximum: 120 }
  validate :restrictions_belong_to_account

  scope :ordered, -> { order(:position, :id) }

  # Boards an account member may open. Administrators see every board; an agent sees the
  # unrestricted ones plus those shared with one of their inboxes or teams. This mirrors
  # ConversationPolicy, which grants an agent a conversation through its inbox or team.
  def self.visible_to(user, account)
    boards = where(account: account)
    return boards if account.administrators.exists?(id: user.id)

    boards.where.not(id: restricted_ids(Custom::Kanban::BoardInbox.all, Custom::Kanban::BoardTeam.all))
          .or(boards.where(id: restricted_ids(
            Custom::Kanban::BoardInbox.where(inbox_id: user.inboxes.where(account_id: account.id).select(:id)),
            Custom::Kanban::BoardTeam.where(team_id: user.teams.where(account_id: account.id).select(:id))
          )))
  end

  # Ids of the boards named by these inbox and team restriction rows.
  def self.restricted_ids(board_inboxes, board_teams)
    where(id: board_inboxes.select(:board_id)).or(where(id: board_teams.select(:board_id))).select(:id)
  end

  def restricted?
    board_inboxes.exists? || board_teams.exists?
  end

  # Pubsub tokens of everyone allowed to see this board, for realtime updates.
  def member_tokens
    admins = account.administrators.pluck(:pubsub_token)
    agents = if restricted?
               inbox_members = User.joins(:inbox_members).where(inbox_members: { inbox_id: board_inboxes.select(:inbox_id) })
               team_members = User.joins(:team_members).where(team_members: { team_id: board_teams.select(:team_id) })
               inbox_members.pluck(:pubsub_token) + team_members.pluck(:pubsub_token)
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
      stages: stages.map(&:push_event_data)
    }
  end

  private

  def restrictions_belong_to_account
    errors.add(:inboxes, :invalid) if inboxes.any? { |inbox| inbox.account_id != account_id }
    errors.add(:teams, :invalid) if teams.any? { |team| team.account_id != account_id }
  end
end
