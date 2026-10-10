require 'rails_helper'

RSpec.describe 'Kanban card tasks', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let(:card) { create(:flow_kanban_card, stage: lead) }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def payload
    response.parsed_body['payload']
  end

  describe 'card tasks' do
    let(:due_at) { 2.days.from_now.iso8601 }

    it 'schedules a task for the agent who creates it and shows the counts on the board' do
      post kanban_url("cards/#{card.id}/tasks"), params: { title: 'Ligar para o cliente', task_type: 'call', due_at: due_at },
                                                 headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(payload).to include('title' => 'Ligar para o cliente', 'task_type' => 'call', 'overdue' => false, 'completed_at' => nil)
      expect(payload['user']['id']).to eq(agent.id)

      get kanban_url("boards/#{board.id}/cards"), headers: agent.create_new_auth_token, as: :json
      tasks = payload.first['cards'].first['tasks']
      expect(tasks).to include('open' => 1, 'overdue' => 0)
      expect(tasks['next_due_at']).to eq(Time.zone.parse(due_at).to_i)
    end

    it 'counts an open task past its date as overdue, and a completed one as neither' do
      overdue = create_task(title: 'Enviar orçamento', due_at: 3.hours.ago)
      create_task(title: 'Reunião', due_at: 1.day.ago, completed_at: 1.hour.ago)

      expect(overdue).to be_overdue
      expect(card.reload.push_event_data[:tasks]).to include(open: 1, overdue: 1)
    end

    it 'completes and reopens a task, stamping the time on the server' do
      task = create_task(title: 'Follow-up')

      patch kanban_url("cards/#{card.id}/tasks/#{task.id}"), params: { completed: true }, headers: agent.create_new_auth_token, as: :json
      expect(payload['completed_at']).to be_present

      patch kanban_url("cards/#{card.id}/tasks/#{task.id}"), params: { completed: false }, headers: agent.create_new_auth_token, as: :json
      expect(payload['completed_at']).to be_nil
    end

    it 'refuses a task assigned to someone outside the account' do
      outsider = create(:user)

      post kanban_url("cards/#{card.id}/tasks"), params: { title: 'Ligar', due_at: due_at, user_id: outsider.id },
                                                 headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Custom::Kanban::CardTask.count).to eq(0)
    end

    it 'refuses a missing due date and an unknown type' do
      post kanban_url("cards/#{card.id}/tasks"), params: { title: 'Ligar' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post kanban_url("cards/#{card.id}/tasks"), params: { title: 'Ligar', due_at: due_at, task_type: 'fax' },
                                                 headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'keeps the tasks of a card an agent cannot see away from them' do
      task = create_task(title: 'Privado')
      # Shared with an inbox the agent is not a member of.
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))

      get kanban_url("cards/#{card.id}/tasks"), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      patch kanban_url("cards/#{card.id}/tasks/#{task.id}"), params: { completed: true }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      delete kanban_url("cards/#{card.id}/tasks/#{task.id}"), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(task.reload).to be_present
    end

    it 'goes away with its card' do
      create_task(title: 'Follow-up')

      expect { card.destroy! }.to change(Custom::Kanban::CardTask, :count).by(-1)
    end

    def create_task(**attributes)
      Custom::Kanban::CardTask.create!({ card: card, user: agent, task_type: 'call', due_at: 1.day.from_now }.merge(attributes))
    end
  end
end
