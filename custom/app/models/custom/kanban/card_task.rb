# A follow-up on a deal: what to do, by when, and who does it. Open until `completed_at` is set.
class Custom::Kanban::CardTask < ApplicationRecord
  TASK_TYPES = %w[call meeting email follow_up custom].freeze

  belongs_to :account
  belongs_to :card, class_name: 'Custom::Kanban::Card', inverse_of: :tasks
  belongs_to :user

  # A task is announced this long before it falls due, and still for this long after: a task
  # that has been overdue for longer is not news, and the badge on the card says so.
  REMINDER_LEAD = 15.minutes
  REMINDER_GRACE = 1.hour

  scope :open_tasks, -> { where(completed_at: nil) }
  scope :overdue, -> { open_tasks.where(due_at: ...Time.current) }
  scope :due_for_reminder, ->(now = Time.current) { open_tasks.where(reminded_at: nil, due_at: (now - REMINDER_GRACE)..(now + REMINDER_LEAD)) }

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 5_000 }
  validates :due_at, presence: true
  validates :task_type, inclusion: { in: TASK_TYPES }
  validate :user_belongs_to_account

  before_validation :inherit_account, on: :create
  after_create :record_created_event
  # A new date, or a task taken up again, is announced again.
  before_update :rearm_reminder, if: -> { will_save_change_to_due_at? || (will_save_change_to_completed_at? && completed_at.nil?) }
  after_update :record_completed_event, if: -> { saved_change_to_completed_at? && completed_at.present? }
  after_update :record_reopened_event, if: -> { saved_change_to_completed_at? && completed_at.nil? }
  after_save :notify_assignee, if: :saved_change_to_user_id?

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

  def record_created_event
    Custom::Kanban::CardEvent.record!(card, 'task_created', { task_id: id, title: title, task_type: task_type, due_at: due_at.to_i })
  end

  def record_reopened_event
    Custom::Kanban::CardEvent.record!(card, 'task_reopened', { task_id: id, title: title })
  end

  def record_completed_event
    Custom::Kanban::CardEvent.record!(card, 'task_completed', { task_id: id, title: title })
  end

  # Whoever is handed the task is told, unless they gave it to themselves.
  def notify_assignee
    Custom::Kanban::Notifier.task_assigned(self, actor: Current.user)
  end

  def rearm_reminder
    self.reminded_at = nil
  end

  def user_belongs_to_account
    errors.add(:user, :invalid) if user && !account&.users&.exists?(id: user_id)
  end
end
