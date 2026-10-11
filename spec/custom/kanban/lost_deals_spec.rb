require 'rails_helper'

RSpec.describe 'Kanban lost deals', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let!(:lost) { create(:flow_kanban_stage, board: board, name: 'Perdido', stage_type: :lost, position: 1) }
  let(:card) { create(:flow_kanban_card, stage: lead) }
  let(:price) { Custom::Kanban::LostReason.create!(account: account, name: 'Preço') }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def payload
    response.parsed_body['payload']
  end

  describe 'the list of reasons' do
    it 'is kept by administrators and read by everyone, with how many deals use each' do
      post kanban_url('lost_reasons'), params: { name: ' Prazo de entrega ' }, headers: admin.create_new_auth_token, as: :json
      expect(payload).to include('name' => 'Prazo de entrega')

      post kanban_url('lost_reasons'), params: { name: 'Outro' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      card.update!(stage: lost, lost_reason: price)
      get kanban_url('lost_reasons'), headers: agent.create_new_auth_token, as: :json
      expect(payload.map { |reason| reason.slice('name', 'deals_count') })
        .to eq([{ 'name' => 'Prazo de entrega', 'deals_count' => 0 }, { 'name' => 'Preço', 'deals_count' => 1 }])
    end

    it 'refuses a name already used in the account, whatever its case, and an empty or long one' do
      price
      ['PREÇO', '', 'x' * 81].each do |name|
        post kanban_url('lost_reasons'), params: { name: name }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_content).or have_http_status(:bad_request)
      end
      expect(Custom::Kanban::LostReason.count).to eq(1)
    end

    it 'keeps the deals when a reason is deleted, without a reason' do
      card.update!(stage: lost, lost_reason: price)

      delete kanban_url("lost_reasons/#{price.id}"), headers: admin.create_new_auth_token, as: :json

      expect(card.reload).to have_attributes(stage: lost, lost_reason_id: nil)
    end
  end

  describe 'losing a deal' do
    it 'keeps the reason and the note, and writes them in the history' do
      patch kanban_url("cards/#{card.id}/move"), params: { stage_id: lost.id, lost_reason_id: price.id, lost_note: 'Achou mais barato' },
                                                 headers: agent.create_new_auth_token, as: :json

      expect(payload).to include('lost_reason' => { 'id' => price.id, 'name' => 'Preço' }, 'lost_note' => 'Achou mais barato')
      expect(card.events.find_by(kind: 'stage_moved').data).to include('lost_reason' => 'Preço', 'lost_note' => 'Achou mais barato')
    end

    it 'may go without a reason' do
      patch kanban_url("cards/#{card.id}/move"), params: { stage_id: lost.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(payload['lost_reason']).to be_nil
    end

    it 'forgets the reason when the deal comes back' do
      card.update!(stage: lost, lost_reason: price, lost_note: 'caro')

      patch kanban_url("cards/#{card.id}/move"), params: { stage_id: lead.id }, headers: agent.create_new_auth_token, as: :json

      expect(card.reload).to have_attributes(lost_reason_id: nil, lost_note: nil)
    end

    it 'refuses a reason of another account and a note past 500 characters' do
      other = Custom::Kanban::LostReason.create!(account: create(:account), name: 'Preço')

      patch kanban_url("cards/#{card.id}/move"), params: { stage_id: lost.id, lost_reason_id: other.id },
                                                 headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      patch kanban_url("cards/#{card.id}/move"), params: { stage_id: lost.id, lost_note: 'x' * 501 },
                                                 headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(card.reload.stage).to eq(lead)
    end
  end
end
