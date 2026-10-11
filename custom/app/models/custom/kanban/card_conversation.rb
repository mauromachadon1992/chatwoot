class Custom::Kanban::CardConversation < ApplicationRecord
  belongs_to :card, class_name: 'Custom::Kanban::Card'
  belongs_to :conversation
  belongs_to :board, class_name: 'Custom::Kanban::Board'

  validates :conversation_id, uniqueness: { scope: :board_id }
  validate :conversation_belongs_to_account

  before_validation { self.board_id ||= card&.board_id }
  after_create { Custom::Kanban::CardEvent.record!(card, 'conversation_linked', { display_id: conversation.display_id }) }

  private

  # Any conversation of the account qualifies, whatever its channel: the card belongs to the
  # contact, and the contact may write from WhatsApp, e-mail, the widget or anywhere else.
  def conversation_belongs_to_account
    errors.add(:conversation, :invalid) if conversation && card && conversation.account_id != card.account_id
  end
end
