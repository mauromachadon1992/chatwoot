require 'rails_helper'

RSpec.describe 'Kanban tasks and stage automations', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let!(:won) { create(:flow_kanban_stage, board: board, name: 'Ganho', stage_type: :won, position: 1) }
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

  describe 'automations API' do
    it 'is for administrators only' do
      get kanban_url("boards/#{board.id}/automations"), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post kanban_url("boards/#{board.id}/automations"),
           params: { stage_id: won.id, trigger_type: 'conversation_status_changed', trigger_config: { status: 'resolved' } },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'creates, lists, updates and deletes a rule' do
      post kanban_url("boards/#{board.id}/automations"),
           params: { stage_id: won.id, trigger_type: 'conversation_status_changed', trigger_config: { status: 'resolved' } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      id = payload['id']
      expect(payload).to include('stage_id' => won.id, 'trigger_config' => { 'status' => 'resolved' }, 'active' => true)

      patch kanban_url("boards/#{board.id}/automations/#{id}"), params: { active: false }, headers: admin.create_new_auth_token, as: :json
      expect(payload['active']).to be(false)

      get kanban_url("boards/#{board.id}/automations"), headers: admin.create_new_auth_token, as: :json
      expect(payload.pluck('id')).to eq([id])

      delete kanban_url("boards/#{board.id}/automations/#{id}"), headers: admin.create_new_auth_token, as: :json
      expect(Custom::Kanban::StageAutomation.count).to eq(0)
    end

    it 'refuses a stage of another board and a config that does not fit the trigger' do
      other_stage = create(:flow_kanban_stage, board: create(:flow_kanban_board, account: account))

      post kanban_url("boards/#{board.id}/automations"),
           params: { stage_id: other_stage.id, trigger_type: 'label_added', trigger_config: { label: 'vip' } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      post kanban_url("boards/#{board.id}/automations"),
           params: { stage_id: won.id, trigger_type: 'conversation_status_changed', trigger_config: { status: 'archived' } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post kanban_url("boards/#{board.id}/automations"),
           params: { stage_id: won.id, trigger_type: 'label_added', trigger_config: { label: '' } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'does not reach the rules of another account' do
      other_board = create(:flow_kanban_board)

      get kanban_url("boards/#{other_board.id}/automations"), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe Custom::Kanban::StageAutomationRunner do
    let(:contact) { card.contact }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open) }

    before { Custom::Kanban::CardConversation.create!(card: card, conversation: conversation) }

    def rule(trigger_type, config, stage: won, **attributes)
      Custom::Kanban::StageAutomation.create!({ board: board, stage: stage, trigger_type: trigger_type, trigger_config: config }.merge(attributes))
    end

    it 'moves the card when its conversation reaches the status, and writes the stage history' do
      rule('conversation_status_changed', { 'status' => 'resolved' })
      conversation.update_columns(status: Conversation.statuses[:resolved]) # rubocop:disable Rails/SkipsModelValidations

      described_class.status_changed(conversation)

      expect(card.reload.stage).to eq(won)
      expect(card.stage_transitions.order(:id).last).to have_attributes(from_stage_id: lead.id, to_stage_id: won.id)
    end

    it 'leaves the card alone for another status, an inactive rule or a card already there' do
      rule('conversation_status_changed', { 'status' => 'resolved' }, active: false)
      rule('conversation_status_changed', { 'status' => 'pending' })
      conversation.update_columns(status: Conversation.statuses[:resolved]) # rubocop:disable Rails/SkipsModelValidations

      described_class.status_changed(conversation)

      expect(card.reload.stage).to eq(lead)
    end

    it 'applies only the oldest matching rule' do
      rule('conversation_status_changed', { 'status' => 'open' }, stage: won)
      rule('conversation_status_changed', { 'status' => 'open' }, stage: create(:flow_kanban_stage, board: board))

      described_class.status_changed(conversation)

      expect(card.reload.stage).to eq(won)
    end

    it 'moves the card only when the label is new on the conversation' do
      rule('label_added', { 'label' => 'vip' })

      described_class.labels_changed(conversation, { 'cached_label_list' => ['urgente', 'urgente, vip'] })
      expect(card.reload.stage).to eq(won)

      card.move_to!(stage: lead)
      described_class.labels_changed(conversation, { 'cached_label_list' => ['vip', 'vip, urgente'] })
      expect(card.reload.stage).to eq(lead)
    end

    it 'ignores the rules of another board' do
      other_board = create(:flow_kanban_board, account: account)
      Custom::Kanban::StageAutomation.create!(board: other_board, stage: create(:flow_kanban_stage, board: other_board),
                                              trigger_type: 'conversation_status_changed', trigger_config: { 'status' => 'open' })

      described_class.status_changed(conversation)

      expect(card.reload.stage).to eq(lead)
    end

    it 'is reached through the conversation listener' do
      rule('label_added', { 'label' => 'vip' })
      event = Events::Base.new('conversation.updated', Time.zone.now,
                               conversation: conversation, changed_attributes: { 'cached_label_list' => [nil, 'vip'] })

      Custom::Kanban::ConversationListener.instance.conversation_updated(event)

      expect(card.reload.stage).to eq(won)
    end
  end
end
