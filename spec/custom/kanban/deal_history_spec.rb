require 'rails_helper'

RSpec.describe 'Kanban deal history', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Admin') }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Bruno Agente') }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let!(:proposal) { create(:flow_kanban_stage, board: board, name: 'Proposta', position: 1) }
  let(:card) { create(:flow_kanban_card, stage: lead) }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def kinds
    card.events.order(:id).pluck(:kind)
  end

  describe 'what is written' do
    it 'starts with the creation, on its stage' do
      expect(card.events.sole).to have_attributes(kind: 'created', data: include('stage_name' => 'Lead', 'source' => 'manual'))
    end

    it 'writes a move with both stage names and who moved it, or that a rule did' do
      patch kanban_url("cards/#{card.id}/move"), params: { stage_id: proposal.id }, headers: agent.create_new_auth_token, as: :json
      by_agent = card.events.where(kind: 'stage_moved').sole
      expect(by_agent.data).to include('from_stage_name' => 'Lead', 'to_stage_name' => 'Proposta')
      expect(by_agent.data).not_to have_key('by_rule')
      expect(by_agent.user).to eq(agent)

      card.reload.move_to!(stage: lead)
      expect(card.events.where(kind: 'stage_moved').order(:id).last).to have_attributes(user: nil, data: include('by_rule' => true))
    end

    it 'writes value and assignee changes' do
      patch kanban_url("cards/#{card.id}"), params: { value_cents: 150_000, assignee_id: agent.id }, headers: admin.create_new_auth_token, as: :json

      events = card.events.where(kind: %w[value_changed assignee_changed]).index_by(&:kind)
      expect(events['value_changed'].data).to include('from_cents' => 0, 'to_cents' => 150_000)
      expect(events['assignee_changed'].data).to include('to_name' => 'Bruno Agente')
      expect(events['value_changed'].user).to eq(admin)
    end

    it 'writes tasks scheduled and done, and conversations linked' do
      task = Custom::Kanban::CardTask.create!(card: card, user: agent, title: 'Ligar', task_type: 'call', due_at: 1.day.from_now)
      task.update!(completed: true)
      conversation = create(:conversation, account: account, contact: card.contact)
      Custom::Kanban::CardConversation.create!(card: card, conversation: conversation)

      expect(kinds).to eq(%w[created task_created task_completed conversation_linked])
      expect(card.events.find_by(kind: 'conversation_linked').data).to eq('display_id' => conversation.display_id)
    end

    it 'writes a task taken up again, so a second completion does not read as a repeat' do
      task = Custom::Kanban::CardTask.create!(card: card, user: agent, title: 'Ligar', task_type: 'call', due_at: 1.day.from_now)

      task.update!(completed: true)
      task.update!(completed: false)
      task.update!(completed: true)

      expect(kinds.last(3)).to eq(%w[task_completed task_reopened task_completed])
    end

    it 'does not write a completion again for a task that is saved while it stays done' do
      task = Custom::Kanban::CardTask.create!(card: card, user: agent, title: 'Ligar', task_type: 'call', due_at: 1.day.from_now)
      task.update!(completed: true)

      task.update!(title: 'Ligar de novo')

      expect(kinds.count('task_completed')).to eq(1)
    end

    it 'writes the move of every deal handed over when a stage is deleted' do
      card
      delete kanban_url("boards/#{board.id}/stages/#{lead.id}"),
             params: { move_to_stage_id: proposal.id }, headers: admin.create_new_auth_token, as: :json

      expect(card.events.where(kind: 'stage_moved').sole.data).to include('from_stage_name' => 'Lead', 'stage_deleted' => true)
    end
  end

  describe 'the History list' do
    it 'comes newest first, a page at a time, with who did it' do
      stub_const('Api::V1::Accounts::Kanban::CardEventsController::PER_PAGE', 2)
      patch kanban_url("cards/#{card.id}/move"), params: { stage_id: proposal.id }, headers: agent.create_new_auth_token, as: :json
      patch kanban_url("cards/#{card.id}"), params: { value_cents: 10_000 }, headers: agent.create_new_auth_token, as: :json

      get kanban_url("cards/#{card.id}/events"), headers: agent.create_new_auth_token, as: :json
      payload = response.parsed_body['payload']
      expect(payload.pluck('kind')).to eq(%w[value_changed stage_moved])
      expect(payload.first['user']).to include('name' => 'Bruno Agente')
      expect(response.parsed_body['meta']).to include('has_more' => true)

      get kanban_url("cards/#{card.id}/events"), params: { page: 2 }, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('kind')).to eq(['created'])
    end

    it 'is not for an agent who cannot see the board' do
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))

      get kanban_url("cards/#{card.id}/events"), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
