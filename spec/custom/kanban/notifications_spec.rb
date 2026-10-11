require 'rails_helper'

RSpec.describe 'Kanban notifications', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let!(:won) { create(:flow_kanban_stage, board: board, name: 'Ganho', stage_type: :won, position: 1) }
  let(:card) { create(:flow_kanban_card, stage: lead, title: 'Obra da Maria') }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def payload
    response.parsed_body['payload']
  end

  def meta
    response.parsed_body['meta']
  end

  def notify(user, **attributes)
    defaults = { account: account, user: user, card: card, kind: 'task_due', data: { task_title: 'Ligar' } }
    Custom::Kanban::Notification.create!(defaults.merge(attributes))
  end

  describe 'who is told' do
    it 'tells an agent a deal was assigned to them, in realtime too' do
      expect do
        patch kanban_url("cards/#{card.id}"), params: { assignee_id: agent.id }, headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(ActionCableBroadcastJob).with(
        [agent.pubsub_token], 'kanban.notification.created',
        hash_including(account_id: account.id, unread_count: 1, notification: hash_including(kind: 'card_assigned', card_id: card.id))
      )

      notification = Custom::Kanban::Notification.find_by!(user: agent)
      expect(notification.data).to include('card_title' => 'Obra da Maria', 'actor_name' => admin.name)
    end

    it 'does not tell an agent about what they did themselves' do
      patch kanban_url("cards/#{card.id}"), params: { assignee_id: agent.id }, headers: agent.create_new_auth_token, as: :json

      expect(Custom::Kanban::Notification.count).to eq(0)
    end

    it 'tells an agent a task was assigned to them, and not when they schedule it for themselves' do
      due = 1.day.from_now.iso8601
      post kanban_url("cards/#{card.id}/tasks"), params: { title: 'Ligar', due_at: due, user_id: agent.id },
                                                 headers: admin.create_new_auth_token, as: :json
      post kanban_url("cards/#{card.id}/tasks"), params: { title: 'Enviar', due_at: due },
                                                 headers: agent.create_new_auth_token, as: :json

      expect(Custom::Kanban::Notification.pluck(:user_id, :kind)).to eq([[agent.id, 'task_assigned']])
      expect(Custom::Kanban::Notification.first.data).to include('task_title' => 'Ligar', 'actor_name' => admin.name)
    end

    it 'tells the agent of a deal that a board rule moved it, and nobody when it has no agent' do
      Custom::Kanban::StageAutomation.create!(board: board, trigger_type: 'conversation_status_changed',
                                              trigger_config: { 'status' => 'open' },
                                              actions: [{ 'type' => 'move_to_stage', 'stage_id' => won.id }])
      conversation = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: card.contact, status: :open)
      Custom::Kanban::CardConversation.create!(card: card, conversation: conversation)

      Custom::Kanban::AutomationRunner.status_changed(conversation)
      expect(Custom::Kanban::Notification.count).to eq(0)

      card.reload.update!(assignee: agent, stage: lead)
      Custom::Kanban::Notification.delete_all
      # The status is reached again: a new episode, which the rule acts on again.
      conversation.update_columns(status_changed_at: 1.minute.from_now) # rubocop:disable Rails/SkipsModelValidations
      Custom::Kanban::AutomationRunner.status_changed(conversation)

      expect(Custom::Kanban::Notification.pluck(:user_id, :kind)).to eq([[agent.id, 'card_moved']])
      expect(Custom::Kanban::Notification.first.data).to include('stage_name' => 'Ganho', 'stage_type' => 'won')
    end

    it 'keeps a reminder as a notification, due soon or overdue' do
      now = Time.current
      Custom::Kanban::CardTask.create!(card: card, user: agent, title: 'Ligar', task_type: 'call', due_at: now + 10.minutes)
      Custom::Kanban::CardTask.create!(card: card, user: agent, title: 'Cobrar', task_type: 'call', due_at: now - 10.minutes)

      Custom::Kanban::TaskReminderJob.perform_now

      kinds = Custom::Kanban::Notification.where(user: agent, kind: %w[task_due task_overdue]).pluck(:kind)
      expect(kinds).to contain_exactly('task_due', 'task_overdue')
    end

    it 'says nothing about a deal on a board the agent cannot see' do
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))

      patch kanban_url("cards/#{card.id}"), params: { assignee_id: agent.id }, headers: admin.create_new_auth_token, as: :json

      expect(Custom::Kanban::Notification.count).to eq(0)
    end
  end

  describe 'the bell' do
    it 'lists only the agent’s own, newest first, with the unread count' do
      old = notify(agent, created_at: 2.hours.ago)
      recent = notify(agent, kind: 'task_overdue')
      notify(admin)
      notify(agent, created_at: 1.hour.ago, read_at: 30.minutes.ago)

      get kanban_url('notifications'), headers: agent.create_new_auth_token, as: :json

      expect(payload.pluck('id')).to eq([recent.id, payload[1]['id'], old.id])
      expect(meta).to include('unread_count' => 2, 'total_count' => 3)
      expect(payload.first).to include('kind' => 'task_overdue', 'card_id' => card.id, 'read_at' => nil)
    end

    it 'hides the notifications of a board the agent no longer sees' do
      notify(agent)
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))

      get kanban_url('notifications'), headers: agent.create_new_auth_token, as: :json

      expect(payload).to be_empty
      expect(meta).to include('unread_count' => 0)
    end

    it 'marks one as read, and all of them' do
      first = notify(agent)
      notify(agent)

      patch kanban_url("notifications/#{first.id}"), headers: agent.create_new_auth_token, as: :json
      expect(payload['read_at']).to be_present
      expect(meta['unread_count']).to eq(1)

      post kanban_url('notifications/read_all'), headers: agent.create_new_auth_token, as: :json
      expect(meta['unread_count']).to eq(0)
    end

    it 'does not let an agent read, or mark, another agent’s notification' do
      others = notify(admin)

      patch kanban_url("notifications/#{others.id}"), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(others.reload).not_to be_read
    end

    it 'does not mark the notifications of another agent when one marks all' do
      mine = notify(agent)
      theirs = notify(admin)

      post kanban_url('notifications/read_all'), headers: agent.create_new_auth_token, as: :json

      expect(mine.reload).to be_read
      expect(theirs.reload).not_to be_read
    end
  end

  describe Custom::Kanban::NotificationCleanupJob do
    it 'drops what was read two weeks ago and what is two months old, and keeps the rest' do
      stale_read = notify(agent, created_at: 20.days.ago, read_at: 15.days.ago)
      ancient = notify(agent, created_at: 70.days.ago)
      fresh_read = notify(agent, created_at: 5.days.ago, read_at: 1.day.ago)
      unread = notify(agent, created_at: 30.days.ago)

      described_class.perform_now

      expect(Custom::Kanban::Notification.where(id: [stale_read.id, ancient.id])).to be_empty
      expect(Custom::Kanban::Notification.where(id: [fresh_read.id, unread.id]).count).to eq(2)
    end
  end
end
