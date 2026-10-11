require 'rails_helper'

# The quote text and totals are built on the server (C5, capability `deal.quote`): the dashboard reads them from the card, an
# agent's HTTP tool from the conversation's deal, and both get the same message.
RSpec.describe 'Kanban quote preview', type: :request do
  let(:nbsp) { [0xA0].pack('U') }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Marcos') }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:stage) { create(:flow_kanban_stage, board: board, name: 'Novo', position: 0) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:deal) { create(:flow_kanban_card, stage: stage, contact: contact, title: 'Concreto') }
  let!(:concrete) { create(:flow_kanban_product, account: account, name: 'Concreto fck 25', sku: 'CON-25', unit: 'm3', price_cents: 48_000) }
  let!(:pump) { create(:flow_kanban_product, account: account, name: 'Bombeamento', sku: 'BOMBA', unit: 'm3', price_cents: 9_000) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    Custom::Kanban::CardConversation.create!(card: deal, conversation: conversation)
    service = Custom::Kanban::CardItemsService.new(deal)
    service.add(product: concrete, attributes: { quantity: 12.5 })
    service.add(product: pump, attributes: { quantity: 12, discount_percent: 10 })
  end

  def card_url(locale = nil)
    "/api/v1/accounts/#{account.id}/kanban/cards/#{deal.id}/quote_preview#{"?locale=#{locale}" if locale}"
  end

  def deal_url(locale = nil)
    "/api/v1/accounts/#{account.id}/kanban/conversations/#{conversation.display_id}/deal/quote#{"?locale=#{locale}" if locale}"
  end

  def payload
    response.parsed_body['payload']
  end

  it 'builds the default message in Portuguese with the totals in cents', :aggregate_failures do
    get card_url('pt_BR'), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(payload['total_cents']).to eq(600_000 + 97_200)
    expect(payload['currency']).to eq('BRL')
    expect(payload['text']).to include('Olá, Marcos!')
    expect(payload['text']).to include("• 12,5 m³ Concreto fck 25 — R$#{nbsp}6.000,00")
    expect(payload['text']).to include("• 12 m³ Bombeamento — R$#{nbsp}972,00 (10% de desconto)")
    expect(payload['text']).to include("Total: R$#{nbsp}6.972,00")
    expect(payload['text']).to end_with('— Ana')
    expect(payload['too_long']).to be(false)
    expect(payload['lines'].pluck('total_cents')).to eq([600_000, 97_200])
  end

  it 'reads in English and Spanish' do
    get card_url('en'), headers: admin.create_new_auth_token, as: :json
    expect(payload['text']).to include('Hi Marcos!').and include('• 12.5 m³ Concreto fck 25 — R$6,000.00').and include('10% off')

    get card_url('es'), headers: admin.create_new_auth_token, as: :json
    expect(payload['text']).to include('¡Hola, Marcos!').and include('10% de descuento')
  end

  it 'uses the account locale without a locale and English for one it has no words for' do
    account.update!(locale: 'pt_BR')
    get card_url, headers: admin.create_new_auth_token, as: :json
    expect(payload['locale']).to eq('pt_BR')

    get card_url('ja'), headers: admin.create_new_auth_token, as: :json
    expect(payload['locale']).to eq('pt_BR')

    account.update!(locale: 'ja')
    get card_url('ja'), headers: admin.create_new_auth_token, as: :json
    expect(payload['locale']).to eq('en')
  end

  it "fills the account's own template and leaves an unknown placeholder as written" do
    account.update!(flow_kanban_quote_template: '{{contact}} / {{deal}} / {{total}} / {{nope}}')
    get card_url('en'), headers: admin.create_new_auth_token, as: :json

    expect(payload['text']).to eq('Marcos / Concreto / R$6,972.00 / {{nope}}')
  end

  it 'warns when the text passes the WhatsApp limit' do
    account.update!(flow_kanban_quote_template: 'x' * 5_000)
    get card_url('en'), headers: admin.create_new_auth_token, as: :json

    expect(payload['too_long']).to be(true)
    expect(payload['length']).to eq(5_000)
  end

  describe 'through the conversation (the agent)' do
    it 'answers the same message without a card id' do
      get card_url('pt_BR'), headers: admin.create_new_auth_token, as: :json
      from_card = payload['text']

      get deal_url('pt_BR'), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(payload['text'].sub(/— .*\z/, '')).to eq(from_card.sub(/— .*\z/, ''))
      expect(payload['total_cents']).to eq(697_200)
    end

    it 'answers 404 when the conversation has no open deal' do
      other = create(:conversation, account: account, inbox: inbox, contact: contact)
      Custom::Kanban::CardConversation.where(conversation: other).delete_all

      get "/api/v1/accounts/#{account.id}/kanban/conversations/#{other.display_id}/deal/quote",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'does not serve an agent without access to the conversation' do
      stranger = create(:user, account: account, role: :agent)

      get deal_url, headers: stranger.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'is announced as a capability' do
      get "/api/v1/accounts/#{account.id}/kanban/settings", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('payload', 'capabilities')).to include('deal.quote')
    end
  end
end
