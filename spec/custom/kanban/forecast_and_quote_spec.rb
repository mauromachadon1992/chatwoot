require 'rails_helper'

RSpec.describe 'Kanban forecast, lost reasons report and quotes', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let!(:proposal) { create(:flow_kanban_stage, board: board, name: 'Proposta', position: 1, win_probability: 80) }
  let!(:won) { create(:flow_kanban_stage, board: board, name: 'Ganho', stage_type: :won, position: 2) }
  let!(:lost) { create(:flow_kanban_stage, board: board, name: 'Perdido', stage_type: :lost, position: 3) }
  let(:today) { Date.new(2026, 10, 8) }

  around { |example| travel_to(today.in_time_zone.change(hour: 10)) { example.run } }

  def deal(stage, value, close_on = nil, **attributes)
    create(:flow_kanban_card, { stage: stage, value_cents: value, expected_close_on: close_on }.merge(attributes))
  end

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  describe Custom::Kanban::ForecastReport do
    it 'sums open deals by close month, weighted by the stage chance, and shows the ones without a date' do
      deal(lead, 100_000, Date.new(2026, 10, 20))       # 50% by default
      deal(proposal, 200_000, Date.new(2026, 10, 31))   # 80%
      deal(proposal, 50_000, Date.new(2026, 9, 30))     # overdue
      deal(lead, 70_000, Date.new(2027, 6, 1))          # after the six months
      deal(lead, 30_000)                                # no date
      deal(won, 999_999, Date.new(2026, 10, 15))        # closed: out

      report = described_class.new(board: board).call
      rows = report[:rows].index_by { |row| row[:key] }

      expect(rows['2026-10']).to include(count: 2, value_cents: 300_000, weighted_cents: 210_000)
      expect(rows['overdue']).to include(count: 1, weighted_cents: 40_000)
      expect(rows['later']).to include(count: 1)
      expect(rows['no_date']).to include(count: 1, value_cents: 30_000)
      expect(report[:rows].pluck(:key)).to eq(%w[overdue 2026-10 2026-11 2026-12 2027-01 2027-02 2027-03 later no_date])
      expect(report).to include(open_count: 5, with_date_count: 4)
      expect(report[:totals]).to include(count: 5, value_cents: 450_000)
    end

    it 'follows the assignee filter' do
      deal(lead, 100_000, Date.new(2026, 10, 20), assignee: agent)
      deal(lead, 100_000, Date.new(2026, 10, 20))

      expect(described_class.new(board: board, assignee_id: agent.id).call[:totals][:count]).to eq(1)
      expect(described_class.new(board: board, assignee_id: 'none').call[:totals][:count]).to eq(1)
    end
  end

  describe Custom::Kanban::LostReasonsReport do
    it 'counts the deals lost in the period by reason, the ones without a reason last' do
      price = Custom::Kanban::LostReason.create!(account: account, name: 'Preço')
      deal(lost, 10_000, lost_reason: price)
      deal(lost, 20_000, lost_reason: price)
      deal(lost, 5_000)
      old = deal(lost, 1_000, lost_reason: price)
      old.update_columns(stage_changed_at: 90.days.ago) # rubocop:disable Rails/SkipsModelValidations

      report = described_class.new(board: board, since: 30.days.ago, until_time: Time.current).call

      expect(report[:rows]).to eq([{ reason_id: price.id, name: 'Preço', count: 2, value_cents: 30_000 },
                                   { reason_id: nil, name: nil, count: 1, value_cents: 5_000 }])
      expect(report[:total]).to eq(3)
    end
  end

  describe 'the report endpoint' do
    it 'answers the funnel, the forecast and the lost reasons together' do
      deal(lead, 100_000, Date.new(2026, 10, 20))

      get kanban_url("boards/#{board.id}/report"), headers: agent.create_new_auth_token

      expect(response.parsed_body['payload'].keys).to include('summary', 'stages', 'forecast', 'lost_reasons')
    end
  end

  describe 'deal fields for the forecast' do
    let(:card) { deal(lead, 0) }

    it 'takes an expected close date, and refuses one absurdly far' do
      patch kanban_url("cards/#{card.id}"), params: { expected_close_on: '2026-11-15' }, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload']['expected_close_on']).to eq('2026-11-15')

      patch kanban_url("cards/#{card.id}"), params: { expected_close_on: '2099-01-01' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'takes a stage chance of 0 to 100, set by an administrator, on open stages only' do
      patch kanban_url("boards/#{board.id}/stages/#{lead.id}"), params: { win_probability: 30 }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload']).to include('win_probability' => 30, 'effective_probability' => 30)

      expect(lead.update(win_probability: 101)).to be(false)
      proposal.update!(stage_type: :won)
      expect(proposal.reload).to have_attributes(win_probability: nil, effective_probability: 100)
    end
  end

  describe 'quotes' do
    let(:inbox) { create(:inbox, account: account) }
    let(:card) { deal(lead, 123_450) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: card.contact) }

    before { Custom::Kanban::CardConversation.create!(card: card, conversation: conversation) }

    it 'writes the quote taken to a conversation in the history' do
      create(:inbox_member, inbox: inbox, user: agent)

      post kanban_url("cards/#{card.id}/quote"), params: { conversation_id: conversation.display_id },
                                                 headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(card.events.find_by(kind: 'quote_prepared').data).to include('display_id' => conversation.display_id, 'total_cents' => 123_450)
    end

    it 'refuses a conversation not linked to the deal, and one the agent cannot open' do
      other = create(:conversation, account: account, inbox: inbox)
      post kanban_url("cards/#{card.id}/quote"), params: { conversation_id: other.display_id }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      post kanban_url("cards/#{card.id}/quote"), params: { conversation_id: conversation.display_id }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'keeps the account quote message, empties it back to the default, and refuses a long one' do
      patch kanban_url('settings'), params: { quote_template: 'Olá {{contact}}' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload']).to include('quote_template' => 'Olá {{contact}}', 'currency' => 'BRL')

      patch kanban_url('settings'), params: { quote_template: '  ' }, headers: admin.create_new_auth_token, as: :json
      expect(account.reload.flow_kanban_quote_template).to be_nil

      patch kanban_url('settings'), params: { quote_template: 'x' * 2001 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      patch kanban_url('settings'), params: { quote_template: 'Oi' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
