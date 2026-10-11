require 'rails_helper'

RSpec.describe 'Kanban stalled-deal alerts', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:proposal) { create(:flow_kanban_stage, board: board, name: 'Proposta', position: 0, stale_after_days: 5) }
  let!(:won) { create(:flow_kanban_stage, board: board, name: 'Ganho', stage_type: :won, position: 1) }
  let(:now) { Time.zone.parse('2026-10-08 10:00:00') }

  around { |example| travel_to(now) { example.run } }

  def card_in(stage, days_ago:, assignee: agent)
    create(:flow_kanban_card, stage: stage, assignee: assignee).tap do |card|
      card.update_columns(stage_changed_at: now - days_ago.days) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  describe 'the stage limit' do
    it 'takes 1 to 365 days, or none' do
      expect(proposal.update(stale_after_days: 0)).to be(false)
      expect(proposal.update(stale_after_days: 366)).to be(false)
      expect(proposal.update(stale_after_days: 1.5)).to be(false)
      expect(proposal.update(stale_after_days: nil)).to be(true)
    end

    it 'goes away when the stage becomes Won or Lost' do
      proposal.update!(stage_type: :won)

      expect(proposal.reload.stale_after_days).to be_nil
    end

    it 'is set by an administrator through the stage API' do
      patch kanban_url("boards/#{board.id}/stages/#{proposal.id}"),
            params: { stale_after_days: 7 }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['stale_after_days']).to eq(7)
    end
  end

  describe 'a stalled deal' do
    it 'says how many days it has been in the stage once it passes the limit' do
      expect(card_in(proposal, days_ago: 6).push_event_data[:stale_days]).to eq(6)
      expect(card_in(proposal, days_ago: 4).push_event_data[:stale_days]).to be_nil
      expect(card_in(won, days_ago: 90).push_event_data[:stale_days]).to be_nil
    end

    it 'is what the stale scope finds' do
      stalled = card_in(proposal, days_ago: 6)
      card_in(proposal, days_ago: 2)
      card_in(won, days_ago: 90)

      expect(Custom::Kanban::Card.stale(now)).to contain_exactly(stalled)
    end
  end

  describe Custom::Kanban::StaleCardsJob do
    it 'tells the agent once per stall, and again after the deal moves and stalls again' do
      card = card_in(proposal, days_ago: 6)

      described_class.perform_now
      described_class.perform_now
      notifications = Custom::Kanban::Notification.where(user: agent, kind: 'card_stale')
      expect(notifications.count).to eq(1)
      expect(notifications.first.data).to include('days' => 6, 'stage_name' => 'Proposta')

      card.move_to!(stage: won)
      card.move_to!(stage: proposal)
      expect(card.reload.stale_notified_at).to be_nil
      card.update_columns(stage_changed_at: now - 8.days) # rubocop:disable Rails/SkipsModelValidations

      described_class.perform_now
      expect(notifications.count).to eq(2)
    end

    it 'claims a stalled deal without an agent and tells nobody' do
      card = card_in(proposal, days_ago: 6, assignee: nil)

      described_class.perform_now

      expect(card.reload.stale_notified_at).to eq(now)
      expect(Custom::Kanban::Notification.count).to eq(0)
    end

    it 'leaves the account alone while the feature is off, and catches up when it is back on' do
      account.update!(flow_kanban_features: [])
      card = card_in(proposal, days_ago: 6)

      described_class.perform_now
      expect(card.reload.stale_notified_at).to be_nil

      account.update!(flow_kanban_features: %w[stale_alerts])
      described_class.perform_now
      expect(Custom::Kanban::Notification.where(kind: 'card_stale').count).to eq(1)
    end

    it 'tells nobody about a deal on a board the agent cannot see' do
      card_in(proposal, days_ago: 6)
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))

      described_class.perform_now

      expect(Custom::Kanban::Notification.where(kind: 'card_stale').count).to eq(0)
    end
  end

  describe 'the Situation filter of the board' do
    it 'shows the stalled deals, or those with an overdue follow-up' do
      stalled = card_in(proposal, days_ago: 6)
      late = card_in(proposal, days_ago: 1)
      Custom::Kanban::CardTask.create!(card: late, user: agent, title: 'Ligar', task_type: 'call', due_at: now - 1.hour)

      get kanban_url("boards/#{board.id}/cards"), params: { status: 'stale' }, headers: agent.create_new_auth_token
      ids = response.parsed_body['payload'].flat_map { |column| column['cards'].pluck('id') }
      expect(ids).to eq([stalled.id])

      get kanban_url("boards/#{board.id}/cards"), params: { status: 'overdue_tasks' }, headers: agent.create_new_auth_token
      ids = response.parsed_body['payload'].flat_map { |column| column['cards'].pluck('id') }
      expect(ids).to eq([late.id])
    end
  end
end
