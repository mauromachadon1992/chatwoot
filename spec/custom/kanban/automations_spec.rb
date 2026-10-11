require 'rails_helper'

RSpec.describe 'Kanban automations', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Bruno Agente') }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let!(:proposal) { create(:flow_kanban_stage, board: board, name: 'Proposta', position: 1, stale_after_days: 3) }
  let!(:won) { create(:flow_kanban_stage, board: board, name: 'Ganho', stage_type: :won, position: 2) }
  let(:card) { create(:flow_kanban_card, stage: lead, assignee: agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: card.contact, status: :open) }
  let(:now) { Time.zone.parse('2026-10-08 10:00:00') }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def payload
    response.parsed_body['payload']
  end

  def move_to(stage)
    { 'type' => 'move_to_stage', 'stage_id' => stage.id }
  end

  def task_action(**attributes)
    { 'type' => 'create_task', 'title' => 'Cobrar retorno', 'task_type' => 'follow_up', 'due_in_hours' => 2,
      'assignee' => 'deal_agent' }.merge(attributes.stringify_keys)
  end

  def rule(trigger, config, actions, **attributes)
    Custom::Kanban::StageAutomation.create!({ board: board, trigger_type: trigger, trigger_config: config, actions: actions }.merge(attributes))
  end

  def events(kind = 'automation_ran')
    card.events.where(kind: kind).order(:id)
  end

  before { Custom::Kanban::CardConversation.create!(card: card, conversation: conversation) }

  describe 'the API' do
    it 'is for administrators only' do
      get kanban_url("boards/#{board.id}/automations"), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      get kanban_url("boards/#{board.id}/automations/runs"), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post kanban_url("boards/#{board.id}/automations"),
           params: { trigger_type: 'deal_created', actions: [move_to(won)] }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'creates, lists, updates and deletes a rule with several actions, keeping their order' do
      post kanban_url("boards/#{board.id}/automations"),
           params: { trigger_type: 'conversation_status_changed', trigger_config: { status: 'resolved' },
                     actions: [move_to(won), task_action(title: 'Pedir avaliação')] },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      id = payload['id']
      expect(payload['actions'].pluck('type')).to eq(%w[move_to_stage create_task])
      expect(payload).to include('active' => true, 'needs_attention' => [])

      patch kanban_url("boards/#{board.id}/automations/#{id}"), params: { active: false }, headers: admin.create_new_auth_token, as: :json
      expect(payload['active']).to be(false)

      get kanban_url("boards/#{board.id}/automations"), headers: admin.create_new_auth_token, as: :json
      expect(payload.pluck('id')).to eq([id])

      delete kanban_url("boards/#{board.id}/automations/#{id}"), headers: admin.create_new_auth_token, as: :json
      expect(Custom::Kanban::StageAutomation.count).to eq(0)
    end

    it 'drops what is not an action and the keys an action does not take' do
      post kanban_url("boards/#{board.id}/automations"),
           params: { trigger_type: 'deal_created',
                     actions: [{ type: 'move_to_stage', stage_id: won.id, title: 'ignored', role: 'admin' }, { type: 'format_disk' }] },
           headers: admin.create_new_auth_token, as: :json

      expect(payload['actions']).to eq([{ 'type' => 'move_to_stage', 'stage_id' => won.id }])
    end

    it 'refuses a rule with no action, with too many, or with a bad one' do
      bad = [
        [],
        Array.new(6) { move_to(won) },
        [move_to(create(:flow_kanban_stage, board: create(:flow_kanban_board, account: account)))],
        [task_action(title: '')],
        [task_action(task_type: 'fax')],
        [task_action(due_in_hours: 721)],
        [task_action(assignee: create(:user).id)],
        [{ 'type' => 'assign_agent', 'user_id' => create(:user).id }],
        [{ 'type' => 'add_label', 'label' => 'does-not-exist' }]
      ]
      bad.each do |actions|
        post kanban_url("boards/#{board.id}/automations"), params: { trigger_type: 'deal_created', actions: actions },
                                                           headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_content).or have_http_status(:bad_request)
      end
      expect(Custom::Kanban::StageAutomation.count).to eq(0)
    end

    it 'refuses a trigger whose settings do not fit' do
      [
        { trigger_type: 'conversation_status_changed', trigger_config: { status: 'archived' } },
        { trigger_type: 'label_added', trigger_config: { label: '' } },
        { trigger_type: 'no_reply', trigger_config: { hours: 0, side: 'customer' } },
        { trigger_type: 'no_reply', trigger_config: { hours: 24, side: 'nobody' } },
        { trigger_type: 'telepathy' }
      ].each do |attributes|
        post kanban_url("boards/#{board.id}/automations"), params: attributes.merge(actions: [move_to(won)]),
                                                           headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_content), "accepted #{attributes.inspect}"
      end
    end

    it 'does not reach the rules of another account' do
      get kanban_url("boards/#{create(:flow_kanban_board).id}/automations"), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'a rule pointing at something deleted' do
    it 'is flagged with what is missing and does not run, even the steps that still could' do
      broken = rule('deal_created', {}, [task_action(title: 'Primeiro contato'), move_to(won)])
      Custom::Kanban::Stage.where(id: won.id).delete_all

      expect(broken.reload.needs_attention).to eq(['stage_missing'])
      expect(broken).not_to be_runnable

      Custom::Kanban::AutomationRunner.deal_created(card)

      expect(card.tasks).to be_empty
      expect(events).to be_empty
    end

    it 'is flagged when its agent or label disappears' do
      label = create(:label, account: account, title: 'vip')
      broken = rule('deal_created', {}, [{ 'type' => 'add_label', 'label' => 'vip' }, { 'type' => 'assign_agent', 'user_id' => agent.id }])
      label.destroy!
      agent.account_users.destroy_all

      expect(broken.reload.needs_attention).to contain_exactly('label_missing', 'agent_missing')
      expect(broken.push_event_data[:needs_attention]).to contain_exactly('label_missing', 'agent_missing')
    end
  end

  describe Custom::Kanban::AutomationRunner do
    it 'runs the actions of a rule in order, and writes what each did in the deal history' do
      rule('conversation_status_changed', { 'status' => 'resolved' },
           [move_to(won), task_action(title: 'Pedir avaliação', due_in_hours: 48)])
      conversation.update!(status: :resolved)

      described_class.status_changed(conversation)

      expect(card.reload.stage).to eq(won)
      task = card.tasks.sole
      expect(task).to have_attributes(title: 'Pedir avaliação', task_type: 'follow_up', user: agent)
      expect(task.due_at).to be_within(1.minute).of(48.hours.from_now)
      expect(events.sole.data['results']).to eq([
                                                  { 'type' => 'move_to_stage', 'status' => 'done', 'stage_name' => 'Ganho' },
                                                  { 'type' => 'create_task', 'status' => 'done', 'title' => 'Pedir avaliação',
                                                    'agent_name' => 'Bruno Agente' }
                                                ])
      expect(events.sole.user).to be_nil
    end

    it 'acts once per episode: the same event twice, or a retried job, changes nothing the second time' do
      automation = rule('conversation_status_changed', { 'status' => 'resolved' }, [task_action])
      conversation.update!(status: :resolved)

      2.times { described_class.status_changed(conversation) }

      expect(card.tasks.count).to eq(1)
      expect(automation.runs.count).to eq(1)
    end

    it 'acts again in a new episode: the status reached once more' do
      rule('conversation_status_changed', { 'status' => 'resolved' }, [task_action])
      conversation.update!(status: :resolved, status_changed_at: 2.hours.ago)
      described_class.status_changed(conversation)

      conversation.update!(status: :resolved, status_changed_at: 1.hour.ago)
      described_class.status_changed(conversation)

      expect(card.tasks.count).to eq(2)
    end

    it 'runs every matching rule, oldest first, so the later move wins' do
      rule('deal_created', {}, [move_to(won)])
      rule('deal_created', {}, [move_to(proposal)])

      described_class.deal_created(card)

      expect(card.reload.stage).to eq(proposal)
      expect(events.count).to eq(2)
    end

    it 'leaves inactive rules and the rules of another board alone' do
      rule('deal_created', {}, [move_to(won)], active: false)
      other = create(:flow_kanban_board, account: account)
      other_stage = create(:flow_kanban_stage, board: other)
      Custom::Kanban::StageAutomation.create!(board: other, trigger_type: 'deal_created', trigger_config: {},
                                              actions: [{ 'type' => 'move_to_stage', 'stage_id' => other_stage.id }])

      described_class.deal_created(card)

      expect(card.reload.stage).to eq(lead)
      expect(events).to be_empty
    end

    it 'stops a rule for the day at its cap, and starts again the next day' do
      automation = rule('deal_created', {}, [task_action])
      stub_const('Custom::Kanban::StageAutomation::RUNS_PER_DAY', 2)
      cards = Array.new(3) { create(:flow_kanban_card, stage: lead, assignee: agent) }

      cards.each { |deal| described_class.deal_created(deal) }
      expect(automation.runs.count).to eq(2)

      travel_to(1.day.from_now) { described_class.deal_created(cards.last) }
      expect(automation.runs.count).to eq(3)
    end

    it 'goes on to the next step when one fails, and says so' do
      rule('deal_created', {}, [task_action, move_to(won)])
      allow(Custom::Kanban::CardTask).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      described_class.deal_created(card)

      expect(card.reload.stage).to eq(won)
      expect(events.sole.data['results'].pluck('status')).to eq(%w[failed done])
    end
  end

  describe 'the actions' do
    it 'move: leaves a deal already there where it is' do
      rule('deal_created', {}, [move_to(lead)])

      described_class = Custom::Kanban::AutomationRunner
      described_class.deal_created(card)

      expect(events.sole.data['results']).to eq([{ 'type' => 'move_to_stage', 'status' => 'skipped', 'reason' => 'already_there' }])
    end

    it 'create task: gives it to the deal’s agent, or to a fixed one, and skips when there is none' do
      rule('deal_created', {}, [task_action(title: 'Do agente')])
      rule('deal_created', {}, [task_action(title: 'Do admin', assignee: admin.id)])
      described_class = Custom::Kanban::AutomationRunner
      described_class.deal_created(card)
      expect(card.tasks.order(:id).map { |task| [task.title, task.user] }).to eq([['Do agente', agent], ['Do admin', admin]])

      orphan = create(:flow_kanban_card, stage: lead)
      described_class.deal_created(orphan)
      result = orphan.events.where(kind: 'automation_ran').order(:id).first.data['results'].first
      expect(result).to include('status' => 'skipped', 'reason' => 'no_agent')
    end

    it 'create task: skips an agent who cannot see the board, and tells nobody about it' do
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))
      rule('deal_created', {}, [task_action(title: 'Invisível')])

      Custom::Kanban::AutomationRunner.deal_created(card)

      expect(card.tasks).to be_empty
      expect(events.sole.data['results'].first).to include('reason' => 'agent_cannot_see_board')
    end

    it 'create task: the agent is told about it, as for any task handed to them' do
      rule('deal_created', {}, [task_action])

      Custom::Kanban::AutomationRunner.deal_created(card)

      expect(Custom::Kanban::Notification.where(user: agent, kind: 'task_assigned').count).to eq(1)
    end

    it 'assign agent: assigns and tells them, and leaves a deal already theirs' do
      rule('deal_created', {}, [{ 'type' => 'assign_agent', 'user_id' => admin.id }])
      Custom::Kanban::AutomationRunner.deal_created(card)

      expect(card.reload.assignee).to eq(admin)
      expect(Custom::Kanban::Notification.where(user: admin, kind: 'card_assigned').count).to eq(1)

      second = create(:flow_kanban_card, stage: lead, assignee: admin)
      Custom::Kanban::AutomationRunner.deal_created(second)
      expect(second.events.where(kind: 'automation_ran').first.data['results'].first).to include('reason' => 'already_assigned')
    end

    it 'add label: labels every linked conversation once, and skips what already has it' do
      create(:label, account: account, title: 'urgente')
      rule('deal_created', {}, [{ 'type' => 'add_label', 'label' => 'urgente' }])

      Custom::Kanban::AutomationRunner.deal_created(card)
      expect(conversation.reload.label_list).to include('urgente')

      labelled = create(:conversation, account: account, inbox: inbox, label_list: ['urgente'])
      # As the API and AutoDealCreator do: the deal and its conversation in one transaction, so the
      # "deal created" rule runs after the commit and sees both.
      again = ActiveRecord::Base.transaction do
        create(:flow_kanban_card, stage: lead).tap { |deal| Custom::Kanban::CardConversation.create!(card: deal, conversation: labelled) }
      end
      expect(again.events.where(kind: 'automation_ran').first.data['results'].first).to include('reason' => 'already_labelled')
    end

    it 'add label: skips a deal with no conversation' do
      create(:label, account: account, title: 'urgente')
      rule('deal_created', {}, [{ 'type' => 'add_label', 'label' => 'urgente' }])
      alone = create(:flow_kanban_card, stage: lead)

      Custom::Kanban::AutomationRunner.deal_created(alone)

      expect(alone.events.where(kind: 'automation_ran').first.data['results'].first).to include('reason' => 'no_conversation')
    end
  end

  describe 'the triggers' do
    it 'deal created: runs when a deal is committed, manual or automatic, and only then' do
      rule('deal_created', {}, [task_action(title: 'Primeiro contato', due_in_hours: 1)])

      fresh = create(:flow_kanban_card, stage: lead, assignee: agent)
      expect(fresh.tasks.pluck(:title)).to eq(['Primeiro contato'])

      fresh.update!(title: 'Outro título')
      expect(fresh.tasks.count).to eq(1)
    end

    it 'label added: runs for a label that is new on the conversation, not for one already there' do
      rule('label_added', { 'label' => 'vip' }, [move_to(won)])
      conversation.update!(label_list: ['vip'], updated_at: 2.hours.ago)

      described_class = Custom::Kanban::AutomationRunner
      described_class.labels_changed(conversation, { 'cached_label_list' => ['vip', 'vip, urgente'] })
      expect(card.reload.stage).to eq(lead)

      described_class.labels_changed(conversation, { 'cached_label_list' => ['urgente', 'urgente, vip'] })
      expect(card.reload.stage).to eq(won)
    end

    it 'stalled: runs once per stay in the stage, when the stage has a limit' do
      rule('deal_stalled', {}, [task_action(title: 'Retomar contato')])
      stalled = create(:flow_kanban_card, stage: proposal, assignee: agent)
      stalled.update_columns(stage_changed_at: 5.days.ago) # rubocop:disable Rails/SkipsModelValidations

      2.times { Custom::Kanban::StaleCardsJob.perform_now }
      expect(stalled.tasks.count).to eq(1)

      stalled.move_to!(stage: lead)
      stalled.move_to!(stage: proposal)
      stalled.update_columns(stage_changed_at: 4.days.ago) # rubocop:disable Rails/SkipsModelValidations
      Custom::Kanban::StaleCardsJob.perform_now
      expect(stalled.tasks.count).to eq(2)
    end

    it 'stalled: runs even when the account turned the stalled alerts off' do
      account.update!(flow_kanban_features: [])
      rule('deal_stalled', {}, [task_action(title: 'Retomar contato')])
      stalled = create(:flow_kanban_card, stage: proposal, assignee: agent)
      stalled.update_columns(stage_changed_at: 5.days.ago) # rubocop:disable Rails/SkipsModelValidations

      Custom::Kanban::StaleCardsJob.perform_now

      expect(stalled.tasks.count).to eq(1)
      expect(Custom::Kanban::Notification.where(kind: 'card_stale')).to be_empty
    end
  end

  describe Custom::Kanban::NoReplyAutomationsJob do
    def message(type, created_at, **attributes)
      create(:message, { account: account, inbox: inbox, conversation: conversation, message_type: type, created_at: created_at }.merge(attributes))
    end

    before { travel_to(now) }

    it 'fires when the customer has not answered for the hours given, once per last message' do
      rule('no_reply', { 'hours' => 24, 'side' => 'customer' }, [task_action(title: 'Cobrar retorno')])
      message(:incoming, now - 3.days)
      message(:outgoing, now - 25.hours)

      2.times { described_class.perform_now }

      expect(card.tasks.pluck(:title)).to eq(['Cobrar retorno'])
    end

    it 'waits until the hours have passed, and ignores the other side' do
      rule('no_reply', { 'hours' => 24, 'side' => 'customer' }, [task_action])
      rule('no_reply', { 'hours' => 24, 'side' => 'agent' }, [task_action(title: 'Responder o cliente')])
      message(:outgoing, now - 23.hours)

      described_class.perform_now
      expect(card.tasks).to be_empty

      travel_to(now + 2.hours)
      described_class.perform_now
      expect(card.tasks.pluck(:title)).to eq(['Cobrar retorno'])
    end

    it 'fires for the team when the customer wrote last and nobody answered' do
      rule('no_reply', { 'hours' => 4, 'side' => 'agent' }, [task_action(title: 'Responder o cliente', due_in_hours: 0)])
      message(:outgoing, now - 2.days)
      message(:incoming, now - 5.hours)

      described_class.perform_now

      expect(card.tasks.pluck(:title)).to eq(['Responder o cliente'])
    end

    it 'acts again after a new message, because that is a new episode' do
      rule('no_reply', { 'hours' => 1, 'side' => 'customer' }, [task_action])
      message(:outgoing, now - 3.hours)
      described_class.perform_now

      message(:outgoing, now - 2.hours)
      described_class.perform_now

      expect(card.tasks.count).to eq(2)
    end

    it 'does not count an internal note or an activity line as the last word' do
      rule('no_reply', { 'hours' => 24, 'side' => 'customer' }, [task_action])
      message(:outgoing, now - 30.hours)
      message(:outgoing, now - 1.hour, private: true)
      message(:activity, now - 1.hour)

      described_class.perform_now

      expect(card.tasks.count).to eq(1)
    end

    it 'leaves alone a conversation silent for more than a month, a closed one and a deal on a closed stage' do
      rule('no_reply', { 'hours' => 24, 'side' => 'customer' }, [task_action])
      message(:outgoing, now - 45.days)
      described_class.perform_now
      expect(card.tasks).to be_empty

      message(:outgoing, now - 30.hours)
      conversation.update!(status: :resolved)
      described_class.perform_now
      expect(card.tasks).to be_empty

      conversation.update!(status: :open)
      card.update!(stage: won)
      described_class.perform_now
      expect(card.tasks).to be_empty
    end
  end

  describe 'the run log' do
    it 'lists what the rules did on the board, newest first, with the deal' do
      rule('deal_created', {}, [move_to(won)])
      first = create(:flow_kanban_card, stage: lead)
      second = create(:flow_kanban_card, stage: lead)

      get kanban_url("boards/#{board.id}/automations/runs"), headers: admin.create_new_auth_token, as: :json

      expect(payload.map { |row| row.dig('card', 'id') }).to eq([second.id, first.id])
      expect(payload.first).to include('kind' => 'automation_ran')
      expect(payload.first['data']['results'].first).to include('status' => 'done', 'stage_name' => 'Ganho')
    end

    it 'does not list the runs of another board' do
      other = create(:flow_kanban_board, account: account)
      other_stage = create(:flow_kanban_stage, board: other)
      Custom::Kanban::StageAutomation.create!(board: other, trigger_type: 'deal_created', trigger_config: {},
                                              actions: [{ 'type' => 'move_to_stage', 'stage_id' => other_stage.id }])
      create(:flow_kanban_card, stage: other_stage)

      get kanban_url("boards/#{board.id}/automations/runs"), headers: admin.create_new_auth_token, as: :json

      expect(payload).to be_empty
    end
  end

  describe 'housekeeping' do
    it 'drops the claims older than their retention, and keeps the recent ones' do
      automation = rule('deal_created', {}, [move_to(won)])
      old = Custom::Kanban::AutomationRun.create!(automation: automation, card: card, episode_key: 'old', created_at: 100.days.ago)
      recent = Custom::Kanban::AutomationRun.create!(automation: automation, card: card, episode_key: 'recent', created_at: 10.days.ago)

      Custom::Kanban::NotificationCleanupJob.perform_now

      expect(Custom::Kanban::AutomationRun.where(id: [old.id, recent.id])).to contain_exactly(recent)
    end

    it 'goes with the rule, and with the deal' do
      automation = rule('deal_created', {}, [move_to(won)])
      Custom::Kanban::AutomationRun.create!(automation: automation, card: card, episode_key: 'x')

      expect { automation.destroy! }.to change(Custom::Kanban::AutomationRun, :count).by(-1)
    end
  end
end
