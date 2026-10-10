require 'rails_helper'

RSpec.describe 'Kanban automatic deals', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:won) { create(:flow_kanban_stage, board: board, name: 'Ganho', stage_type: :won, position: 0) }
  let!(:first_open) { create(:flow_kanban_stage, board: board, name: 'Novo', position: 1) }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza') }

  # Created before the rule is on, so the conversation's own creation event does nothing here.
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent) }

  def enable!(cap: 50, inbox_ids: [inbox.id], feature: true)
    account.update!(flow_kanban_features: feature ? %w[auto_create] : [])
    board.update!(auto_create: { enabled: true, inbox_ids: inbox_ids, daily_cap: cap })
  end

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  describe Custom::Kanban::AutoDealCreator do
    it 'opens one deal on the first open stage, linked, assigned and waiting for review' do
      enable!

      expect { described_class.perform(conversation) }.to have_enqueued_job(ActionCableBroadcastJob).at_least(:once)

      card = board.cards.sole
      expect(card).to have_attributes(stage: first_open, contact: contact, title: 'Maria Souza', source: 'automatic',
                                      needs_review: true, assignee: agent, created_by: nil)
      expect(card.conversations).to eq([conversation])
      expect(Custom::Kanban::Notification.where(user: agent).pluck(:kind)).to eq(['card_assigned'])
    end

    it 'does nothing while the account feature is off, the rule is off, or the inbox is not watched' do
      enable!(feature: false)
      described_class.perform(conversation)

      account.update!(flow_kanban_features: %w[auto_create])
      board.update!(auto_create: { enabled: false })
      described_class.perform(conversation)

      board.update!(auto_create: { enabled: true, inbox_ids: [other_inbox.id] })
      described_class.perform(conversation)

      expect(board.cards).to be_empty
    end

    it 'gives a contact with an open deal no second one, but one whose deals all closed a new one' do
      enable!
      existing = create(:flow_kanban_card, stage: first_open, contact: contact)

      described_class.perform(conversation)
      expect(board.cards.count).to eq(1)

      existing.update!(stage: won)
      described_class.perform(conversation)
      expect(board.cards.where(source: 'automatic').count).to eq(1)
    end

    it 'opens a single deal when the same event is handled twice' do
      enable!

      2.times { described_class.perform(conversation) }

      expect(board.cards.count).to eq(1)
    end

    it 'skips group conversations' do
      enable!
      conversation.update_columns(group_type: Conversation.group_types[:group]) # rubocop:disable Rails/SkipsModelValidations

      described_class.perform(conversation)

      expect(board.cards).to be_empty
    end

    it 'stops at the board’s daily cap' do
      enable!(cap: 1)
      second = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))

      described_class.perform(conversation)
      described_class.perform(second)

      expect(board.cards.count).to eq(1)
      expect(board.auto_created_today).to eq(1)
    end

    it 'leaves the deal unassigned when the conversation has no agent' do
      enable!
      conversation.update!(assignee: nil)

      described_class.perform(conversation)

      expect(board.cards.sole.assignee).to be_nil
    end

    it 'is reached through the conversation listener' do
      enable!
      event = Events::Base.new('conversation.created', Time.zone.now, conversation: conversation)

      Custom::Kanban::ConversationListener.instance.conversation_created(event)

      expect(board.cards.count).to eq(1)
    end
  end

  describe 'the rule in the board settings' do
    it 'is saved by an administrator and shown with the board' do
      patch kanban_url("boards/#{board.id}"), params: { auto_create: { enabled: true, inbox_ids: [inbox.id], daily_cap: 20 } },
                                              headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['auto_create']).to eq('enabled' => true, 'inbox_ids' => [inbox.id], 'daily_cap' => 20,
                                                                   'created_today' => 0)
    end

    it 'refuses a cap out of range, an inbox of another account and an enabled rule without inboxes' do
      [
        { enabled: true, inbox_ids: [inbox.id], daily_cap: 0 },
        { enabled: true, inbox_ids: [inbox.id], daily_cap: 501 },
        { enabled: true, inbox_ids: [create(:inbox).id] },
        { enabled: true, inbox_ids: [] }
      ].each do |rule|
        patch kanban_url("boards/#{board.id}"), params: { auto_create: rule }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_content), "accepted #{rule.inspect}"
      end
      expect(board.reload.auto_create['enabled']).to be(false)
    end

    it 'is not for agents' do
      patch kanban_url("boards/#{board.id}"), params: { auto_create: { enabled: true, inbox_ids: [inbox.id] } },
                                              headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'review' do
    let(:card) do
      enable!
      Custom::Kanban::AutoDealCreator.perform(conversation).first
    end

    it 'ends when an agent changes the deal' do
      patch kanban_url("cards/#{card.id}"), params: { title: 'Obra da Maria' }, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to include('needs_review' => false, 'source' => 'automatic')
    end

    it 'ends when an agent accepts it as it is' do
      patch kanban_url("cards/#{card.id}"), params: { reviewed: true }, headers: agent.create_new_auth_token, as: :json

      expect(card.reload).to have_attributes(needs_review: false, title: 'Maria Souza')
    end

    it 'goes on when only a rule moved the deal' do
      card.move_to!(stage: won)

      expect(card.reload.needs_review).to be(true)
    end
  end
end
