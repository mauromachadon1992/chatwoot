require 'rails_helper'

RSpec.describe 'Kanban values API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let!(:proposal) { create(:flow_kanban_stage, board: board, name: 'Proposta', position: 1) }
  let!(:won) { create(:flow_kanban_stage, board: board, name: 'Ganho', stage_type: :won, position: 2) }
  let!(:lost) { create(:flow_kanban_stage, board: board, name: 'Perdido', stage_type: :lost, position: 3) }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def payload
    response.parsed_body['payload']
  end

  describe 'products' do
    it 'lets administrators keep the catalog and every member search it' do
      post kanban_url('products'), params: { name: 'Cimento CP II 50kg' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post kanban_url('products'), params: { name: ' Cimento CP II 50kg ', sku: 'CIM-50', unit: 'sc', price_cents: 3_990 },
                                   headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(payload).to include('name' => 'Cimento CP II 50kg', 'sku' => 'CIM-50', 'unit' => 'sc', 'price_cents' => 3_990)

      create(:flow_kanban_product, account: account, name: 'Areia média', active: false)
      create(:flow_kanban_product, name: 'Cimento de outra conta')

      get kanban_url('products'), params: { q: 'cim' }, headers: agent.create_new_auth_token, as: :json
      expect(payload.pluck('name')).to eq(['Cimento CP II 50kg'])

      get kanban_url('products'), params: { active: true }, headers: agent.create_new_auth_token, as: :json
      expect(payload.pluck('name')).to eq(['Cimento CP II 50kg'])
      expect(response.parsed_body['meta']).to include('count' => 1, 'page' => 1)
    end

    it 'refuses a code already used in the account, a negative price and an unknown unit' do
      create(:flow_kanban_product, account: account, sku: 'CIM-50')

      post kanban_url('products'), params: { name: 'Outro', sku: 'CIM-50' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post kanban_url('products'), params: { name: 'Outro', price_cents: -1 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post kanban_url('products'), params: { name: 'Outro', unit: 'barril' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'keeps the lines of a deleted product on the deals' do
      product = create(:flow_kanban_product, account: account, price_cents: 2_500)
      card = create(:flow_kanban_card, stage: lead)
      Custom::Kanban::CardItemsService.new(card).add(product: product)

      delete kanban_url("products/#{product.id}"), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      item = card.items.reload.first
      expect(item.product_id).to be_nil
      expect(item.name).to eq(product.name)
      expect(card.reload.value_cents).to eq(2_500)
    end
  end

  describe 'card value and items' do
    let(:card) { create(:flow_kanban_card, stage: lead) }
    let(:cement) { create(:flow_kanban_product, account: account, name: 'Cimento', unit: 'sc', price_cents: 3_990) }
    let(:sand) { create(:flow_kanban_product, account: account, name: 'Areia', unit: 'm3', price_cents: 12_000) }

    it 'takes a typed value while the deal has no products' do
      patch kanban_url("cards/#{card.id}"), params: { value_cents: 150_000 }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(payload).to include('value_cents' => 150_000, 'items_count' => 0, 'items' => [])
    end

    it 'values the deal by its products, each priced and discounted on its own line' do
      post kanban_url("cards/#{card.id}/items"), params: { product_id: cement.id, quantity: '10' }, headers: agent.create_new_auth_token, as: :json
      expect(payload['value_cents']).to eq(39_900)

      post kanban_url("cards/#{card.id}/items"), params: { product_id: sand.id, quantity: '2.5', discount_percent: '10' },
                                                 headers: agent.create_new_auth_token, as: :json
      expect(payload['items'].pluck('name')).to eq(%w[Cimento Areia])
      expect(payload['items'].last).to include('unit' => 'm3', 'quantity' => '2.5', 'total_cents' => 27_000)
      expect(payload['value_cents']).to eq(66_900)

      line = payload['items'].first
      patch kanban_url("cards/#{card.id}/items/#{line['id']}"), params: { unit_price_cents: 3_500 },
                                                                headers: agent.create_new_auth_token, as: :json
      expect(payload['value_cents']).to eq(62_000)
    end

    it 'keeps the price a product had when it was added' do
      Custom::Kanban::CardItemsService.new(card).add(product: cement, attributes: { quantity: 2 })
      cement.update!(price_cents: 9_999)

      get kanban_url("cards/#{card.id}"), headers: agent.create_new_auth_token, as: :json

      expect(payload['items'].first['unit_price_cents']).to eq(3_990)
      expect(payload['value_cents']).to eq(7_980)
    end

    it 'refuses a typed value while products set it, and frees it once they are gone' do
      post kanban_url("cards/#{card.id}/items"), params: { product_id: cement.id }, headers: agent.create_new_auth_token, as: :json
      line = payload['items'].first

      patch kanban_url("cards/#{card.id}"), params: { value_cents: 1 }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      delete kanban_url("cards/#{card.id}/items/#{line['id']}"), headers: agent.create_new_auth_token, as: :json
      expect(payload).to include('items_count' => 0, 'value_cents' => 3_990)

      patch kanban_url("cards/#{card.id}"), params: { value_cents: 1 }, headers: agent.create_new_auth_token, as: :json
      expect(payload['value_cents']).to eq(1)
    end

    it 'refuses inactive products, products of another account and impossible quantities' do
      inactive = create(:flow_kanban_product, account: account, active: false)
      foreign = create(:flow_kanban_product)

      post kanban_url("cards/#{card.id}/items"), params: { product_id: inactive.id }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      post kanban_url("cards/#{card.id}/items"), params: { product_id: foreign.id }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      post kanban_url("cards/#{card.id}/items"), params: { product_id: cement.id, quantity: '0' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(card.reload.items_count).to eq(0)
    end

    it 'gives the board the value of each stage, whatever the conversations linked to its cards' do
      inbox = create(:inbox, account: account)
      card.update!(value_cents: 10_000)
      create_list(:conversation, 2, account: account, inbox: inbox, contact: card.contact).each do |conversation|
        card.card_conversations.create!(conversation: conversation)
      end
      create(:flow_kanban_card, stage: lead, value_cents: 5_000)

      get kanban_url("boards/#{board.id}/cards"), headers: agent.create_new_auth_token, as: :json

      column = payload.find { |entry| entry['stage_id'] == lead.id }
      expect(column).to include('total' => 2, 'total_value_cents' => 15_000)
      expect(column['cards'].first).to include('value_cents', 'items_count')
      expect(column['cards'].first).not_to have_key('items')
    end
  end

  describe 'stage history' do
    it 'records where a card was created, every move, and the cards a deleted stage hands over' do
      card = create(:flow_kanban_card, stage: lead)
      card.move_to!(stage: proposal)

      delete kanban_url("boards/#{board.id}/stages/#{proposal.id}"), params: { move_to_stage_id: won.id },
                                                                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      history = card.stage_transitions.order(:created_at, :id).pluck(:from_stage_id, :to_stage_id)
      expect(history).to eq([[nil, lead.id], [lead.id, proposal.id], [proposal.id, won.id]])
    end
  end

  describe 'report' do
    let(:since) { 10.days.ago.beginning_of_day }

    def report(params = {}, user: admin)
      get kanban_url("boards/#{board.id}/report"), params: { since: since.to_i, until: Time.current.to_i }.merge(params),
                                                   headers: user.create_new_auth_token, as: :json
      payload
    end

    # Each deal is created `days` ago and walks the stages one day apart.
    def deal(path, value_cents: 0, days: 5, assignee: nil)
      travel_to(days.days.ago) do
        card = create(:flow_kanban_card, stage: path.first, value_cents: value_cents, assignee: assignee)
        path.drop(1).each do |stage|
          travel 1.day
          card.move_to!(stage: stage)
        end
        card
      end
    end

    it 'sums what is open, won and lost, and how long won deals took' do
      deal([lead], value_cents: 1_000)
      deal([lead, proposal], value_cents: 2_000)
      deal([lead, proposal, won], value_cents: 30_000)
      deal([lead, won], value_cents: 10_000)
      deal([lead, lost], value_cents: 7_000)

      summary = report['summary']

      expect(summary['created']).to eq(5)
      expect(summary['open']).to eq('count' => 2, 'value_cents' => 3_000)
      expect(summary['won']).to eq('count' => 2, 'value_cents' => 40_000)
      expect(summary['lost']).to eq('count' => 1, 'value_cents' => 7_000)
      expect(summary['win_rate']).to eq(66.7)
      expect(summary['average_won_cents']).to eq(20_000)
      expect(summary['average_cycle_seconds']).to be_within(5).of(1.5.days.to_i)
    end

    it 'tells the dashboard the currency and the period it covers' do
      expect(report).to include('currency' => 'BRL', 'since' => since.to_i)
    end

    it 'counts how far the deals created in the period got, a won deal passing every open stage' do
      deal([lead])
      deal([lead, proposal])
      deal([lead, proposal, won])
      deal([lead, won])
      deal([lead, lost])
      deal([lead], days: 20)

      stages = report['stages'].index_by { |stage| stage['name'] }

      expect(stages['Lead']).to include('reached' => 5, 'conversion_rate' => 100.0, 'count' => 2)
      expect(stages['Proposta']).to include('reached' => 3, 'conversion_rate' => 60.0)
      expect(stages['Ganho']).to include('reached' => 2, 'conversion_rate' => 66.7)
      expect(stages['Perdido']).to include('reached' => nil, 'conversion_rate' => nil, 'count' => 1)
      expect(stages['Lead']['average_seconds']).to be_within(5).of(1.day.to_i)
    end

    it 'narrows everything to one assignee, or to the unassigned deals' do
      deal([lead, won], value_cents: 5_000, assignee: agent)
      deal([lead, won], value_cents: 9_000)

      expect(report({ assignee_id: agent.id })['summary']['won']).to eq('count' => 1, 'value_cents' => 5_000)
      expect(report({ assignee_id: 'none' })['summary']['won']).to eq('count' => 1, 'value_cents' => 9_000)
    end

    it 'answers an empty period without dividing by zero' do
      summary = report['summary']

      expect(summary).to include('created' => 0, 'win_rate' => nil, 'average_won_cents' => nil, 'average_cycle_seconds' => nil)
      expect(report['stages'].pluck('reached')).to all(be_nil)
    end

    it 'hides the report of a board the agent cannot see' do
      board.update!(inboxes: [create(:inbox, account: account)])

      report({}, user: agent)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'settings' do
    it 'keeps one currency per account, set by administrators' do
      get kanban_url('settings'), headers: agent.create_new_auth_token, as: :json
      expect(payload).to include('currency' => 'BRL')
      expect(payload['currencies']).to include('BRL', 'USD', 'EUR')

      patch kanban_url('settings'), params: { currency: 'USD' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      patch kanban_url('settings'), params: { currency: 'XYZ' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      patch kanban_url('settings'), params: { currency: 'USD' }, headers: admin.create_new_auth_token, as: :json
      expect(payload['currency']).to eq('USD')
      expect(account.reload.settings['flow_kanban_currency']).to eq('USD')
    end
  end
end
