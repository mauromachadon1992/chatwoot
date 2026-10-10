require 'rails_helper'

# The deal of a conversation and its product lines, for the fazer.ai agents (B-13b): keyed by the conversation, so the
# agent never names a card; the price is the catalog's; one line per product.
RSpec.describe 'Kanban conversation deal', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:service) { create(:user, account: account, role: :administrator, name: 'Agente IA') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Novo', position: 0) }
  let!(:won) { create(:flow_kanban_stage, board: board, name: 'Ganho', position: 1, stage_type: :won) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:deal) { create(:flow_kanban_card, stage: lead, contact: contact, title: 'Concreto') }
  let!(:concrete) { create(:flow_kanban_product, account: account, name: 'Concreto fck 25', sku: 'CON-25', unit: 'm3', price_cents: 48_000) }
  let!(:pump) { create(:flow_kanban_product, account: account, name: 'Bombeamento', sku: 'BOMBA', unit: 'm3', price_cents: 9_000) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    Custom::Kanban::CardConversation.create!(card: deal, conversation: conversation)
  end

  def url(suffix = '', display_id: conversation.display_id)
    "/api/v1/accounts/#{account.id}/kanban/conversations/#{display_id}/deal#{suffix}"
  end

  def as(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def body
    response.parsed_body
  end

  def lines
    body.dig('payload', 'items')
  end

  describe 'reading the deal' do
    it 'answers with the open deal of the conversation and its lines' do
      Custom::Kanban::CardItemsService.new(deal).add(product: concrete, attributes: { quantity: 2 })

      as(agent, :get, url)

      expect(response).to have_http_status(:ok)
      expect(body['payload']).to include('id' => deal.id, 'title' => 'Concreto', 'value_cents' => 96_000)
      expect(lines.map { |line| line.slice('product_id', 'quantity', 'unit_price_cents') })
        .to eq([{ 'product_id' => concrete.id, 'quantity' => '2.0', 'unit_price_cents' => 48_000 }])
    end

    it 'is a 404 with a message when the conversation has no open deal' do
      deal.update!(stage: won)

      as(agent, :get, url)

      expect(response).to have_http_status(:not_found)
      expect(body['message']).to be_present
    end

    it 'takes the most recently updated of several open deals, and never reaches a deal of another conversation' do
      other_stage = create(:flow_kanban_stage, board: create(:flow_kanban_board, account: account), name: 'Novo', position: 0)
      newer = create(:flow_kanban_card, stage: other_stage, contact: contact, title: 'Mais novo')
      Custom::Kanban::CardConversation.create!(card: newer, conversation: conversation)
      foreign = create(:flow_kanban_card, stage: lead, contact: create(:contact, account: account), title: 'De outra conversa')
      newer.update!(title: 'Mais novo, editado')

      as(agent, :get, url)
      expect(body.dig('payload', 'id')).to eq(newer.id)
      expect(body.dig('payload', 'id')).not_to eq(foreign.id)
    end

    it 'is refused to someone who cannot see the conversation' do
      other = create(:user, account: account, role: :agent)

      as(other, :get, url)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'is a 404 for a conversation that does not exist' do
      as(agent, :get, url(display_id: 999_999))

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'adding a product' do
    it 'adds the line at the catalog price, and the deal is worth the sum' do
      as(service, :post, url('/items'), product_id: concrete.id, quantity: 12)
      as(service, :post, url('/items'), product_id: pump.id, quantity: 12)

      expect(response).to have_http_status(:ok)
      expect(body.dig('payload', 'value_cents')).to eq((12 * 48_000) + (12 * 9_000))
      expect(lines.map { |line| line['name'] }).to contain_exactly('Concreto fck 25', 'Bombeamento')
      expect(deal.reload.value_cents).to eq(684_000)
    end

    it 'ignores a price or a discount the agent sends: only the quantity is its own' do
      as(service, :post, url('/items'), product_id: concrete.id, quantity: 1, unit_price_cents: 1, discount_percent: 90)

      expect(lines.first).to include('unit_price_cents' => 48_000, 'discount_percent' => '0.0')
      expect(deal.reload.value_cents).to eq(48_000)
    end

    it 'sets the quantity when the product is already on the deal, so there is one line per product' do
      as(service, :post, url('/items'), product_id: concrete.id, quantity: 2)
      as(service, :post, url('/items'), product_id: concrete.id, quantity: 5)

      expect(lines.size).to eq(1)
      expect(deal.reload.value_cents).to eq(5 * 48_000)
    end

    it 'takes a fractional quantity' do
      as(service, :post, url('/items'), product_id: concrete.id, quantity: 2.5)

      expect(deal.reload.value_cents).to eq(120_000)
    end

    it 'refuses a quantity that is not a number above zero, and a product that does not exist or is inactive' do
      [0, -3, 'muitos', nil, 1_000_000_000].each do |quantity|
        as(service, :post, url('/items'), product_id: concrete.id, quantity: quantity)
        expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:bad_request)
      end

      as(service, :post, url('/items'), product_id: 0, quantity: 1)
      expect(response).to have_http_status(:not_found)

      concrete.update!(active: false)
      as(service, :post, url('/items'), product_id: concrete.id, quantity: 1)
      expect(response).to have_http_status(:not_found)
      expect(deal.reload.items).to be_empty
    end

    it 'does not take a product of another account' do
      foreign = create(:flow_kanban_product, account: create(:account))

      as(service, :post, url('/items'), product_id: foreign.id, quantity: 1)

      expect(response).to have_http_status(:not_found)
    end

    it 'holds at most 50 lines' do
      stub_const('Api::V1::Accounts::Kanban::ConversationDealsController::MAX_LINES', 1)
      as(service, :post, url('/items'), product_id: concrete.id, quantity: 1)
      as(service, :post, url('/items'), product_id: pump.id, quantity: 1)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(deal.reload.items.count).to eq(1)
    end

    it 'records who changed the value: the agents\' service user, as an agent bot' do
      Custom::Kanban::ServiceUser.mark!(service)

      as(service, :post, url('/items'), product_id: concrete.id, quantity: 3)

      expect(deal.events.where(kind: 'value_changed').last).to have_attributes(actor_kind: 'agent_bot', actor_name: 'Agente IA')
    end
  end

  describe 'removing a product' do
    it 'removes the line by product id and the deal is worth what is left' do
      as(service, :post, url('/items'), product_id: concrete.id, quantity: 1)
      as(service, :post, url('/items'), product_id: pump.id, quantity: 1)

      as(service, :delete, url("/items/#{pump.id}"))

      expect(response).to have_http_status(:ok)
      expect(lines.map { |line| line['product_id'] }).to eq([concrete.id])
      expect(deal.reload.value_cents).to eq(48_000)
    end

    it 'is a 404 for a product that is not on the deal' do
      as(service, :delete, url("/items/#{pump.id}"))

      expect(response).to have_http_status(:not_found)
    end
  end

  it 'is announced in the capabilities' do
    as(agent, :get, "/api/v1/accounts/#{account.id}/kanban/settings")

    expect(body.dig('payload', 'capabilities')).to include('deal.items', 'products.read')
  end
end
