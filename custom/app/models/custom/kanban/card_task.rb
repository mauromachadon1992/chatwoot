# A follow-up on a deal: what to do, by when, and who does it. Open until `completed_at` is set.
class Custom::Kanban::CardTask < ApplicationRecord
  TASK_TYPES = %w[call meeting email follow_up custom].freeze

  belongs_to :account
  belongs_to :card, class_name: 'Custom::Kanban::Card', inverse_of: :tasks
  belongs_to :user

  scope :open_tasks, -> { where(completed_at: nil) }
  scope :overdue, -> { open_tasks.where(due_at: ...Time.current) }

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 5_000 }
  validates :due_at, presence: true
  validates :task_type, inclusion: { in: TASK_TYPES }
  validate :user_belongs_to_account

  before_validation :inherit_account, on: :create

  def completed?
    completed_at.present?
  end

  def overdue?
    !completed? && due_at < Time.current
  end

  # The checkbox of the dashboard: done or not, the server stamps the time.
  def completed=(done)
    self.completed_at = ActiveModel::Type::Boolean.new.cast(done) ? (completed_at || Time.current) : nil
  end

  def push_event_data
    {
      id: id,
      card_id: card_id,
      title: title,
      description: description,
      task_type: task_type,
      due_at: due_at.to_i,
      completed_at: completed_at&.to_i,
      overdue: overdue?,
      user: user.push_event_data,
      created_at: created_at.to_i
    }
  end

  private

  def inherit_account
    self.account_id ||= card&.account_id
  end

  def user_belongs_to_account
    errors.add(:user, :invalid) if user && !account&.users&.exists?(id: user_id)
  end
end
