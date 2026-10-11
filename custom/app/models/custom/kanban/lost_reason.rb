# Why deals are lost, a list an administrator keeps per account. A deal moved to a lost stage
# may carry one; deleting a reason keeps the deals and empties theirs.
class Custom::Kanban::LostReason < ApplicationRecord
  NAME_MAX_LENGTH = 80

  belongs_to :account

  before_validation :strip_name

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }
  validate :name_unique_in_account

  scope :ordered, -> { order(Arel.sql('lower(name)'), :id) }

  def push_event_data
    { id: id, name: name }
  end

  private

  def strip_name
    self.name = name.to_s.squish
  end

  def name_unique_in_account
    taken = self.class.where(account_id: account_id).where.not(id: id).exists?(['lower(name) = ?', name.to_s.downcase])
    errors.add(:name, :taken) if taken
  end
end
