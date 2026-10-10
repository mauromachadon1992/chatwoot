require 'rails_helper'

# B-10: a conversation an agent bot answers starts `pending` and hides under the default "Open" filter, so the card says
# who has it (`handled_by_agent` on each linked conversation).
RSpec.describe Custom::Kanban::Card, '#push_event_data' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let(:stage) { create(:flow_kanban_stage, board: board) }
  let(:card) { create(:flow_kanban_card, stage: stage, contact: contact) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending) }

  def handled
    Custom::Kanban::Card.preloaded.find(card.id).push_event_data[:conversations].first[:handled_by_agent]
  end

  before { Custom::Kanban::CardConversation.create!(card: card, conversation: conversation) }

  it 'is false for a pending conversation of an inbox without an agent bot' do
    expect(handled).to be(false)
  end

  it 'is true for a pending conversation of an inbox with an active agent bot' do
    AgentBotInbox.create!(inbox: inbox, agent_bot: create(:agent_bot, account: account))

    expect(handled).to be(true)
  end

  it 'is false once a human has it open, or when the bot is inactive' do
    bot_inbox = AgentBotInbox.create!(inbox: inbox, agent_bot: create(:agent_bot, account: account))
    conversation.update!(status: :open)
    expect(handled).to be(false)

    conversation.update!(status: :pending)
    bot_inbox.update!(status: :inactive)
    expect(handled).to be(false)
  end
end
