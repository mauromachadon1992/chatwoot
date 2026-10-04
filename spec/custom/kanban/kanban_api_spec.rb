require 'rails_helper'

RSpec.describe 'Kanban API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:widget_inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:inbox, :with_email, account: account) }
  let(:api_inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:contact) { create(:contact, account: account) }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  # Conversations are created past a few others so that a display id never equals the internal
  # id: matching on the wrong key must fail these specs, not pass them by coincidence.
  def conversation_in(inbox)
    create_list(:conversation, 2, account: account, inbox: create(:inbox, account: account))
    create(:conversation, account: account, inbox: inbox, contact: contact)
  end

  describe 'boards' do
    it 'creates a board with the default stages, for administrators only' do
      post kanban_url('boards'), params: { name: 'Vendas' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post kanban_url('boards'), params: { name: 'Vendas', inbox_ids: [email_inbox.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      board = response.parsed_body['payload']
      expect(board['stages'].pluck('stage_type')).to eq(%w[open open won lost])
      expect(board['inbox_ids']).to eq([email_inbox.id])
    end

    it 'ignores inboxes of another account' do
      foreign_inbox = create(:inbox)

      post kanban_url('boards'), params: { name: 'Vendas', inbox_ids: [foreign_inbox.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['inbox_ids']).to be_empty
    end

    it 'shows an agent the open boards and those of their inboxes or teams' do
      team = create(:team, account: account)
      create(:team_member, team: team, user: agent)
      create(:inbox_member, inbox: widget_inbox, user: agent)

      open_board = create(:flow_kanban_board, account: account)
      inbox_board = create(:flow_kanban_board, account: account, inboxes: [widget_inbox])
      team_board = create(:flow_kanban_board, account: account, teams: [team])
      hidden_board = create(:flow_kanban_board, account: account, inboxes: [email_inbox])

      get kanban_url('boards'), headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(open_board.id, inbox_board.id, team_board.id)

      get kanban_url("boards/#{hidden_board.id}"), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      get kanban_url('boards'), headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].length).to eq(4)
    end
  end

  describe 'stages' do
    let(:board) { create(:flow_kanban_board, account: account) }
    let(:stage) { create(:flow_kanban_stage, board: board) }
    let(:target) { create(:flow_kanban_stage, board: board) }

    it 'hands the cards of a deleted stage to another one' do
      card = create(:flow_kanban_card, stage: stage)

      delete kanban_url("boards/#{board.id}/stages/#{stage.id}"), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(card.reload.stage).to eq(stage)

      delete kanban_url("boards/#{board.id}/stages/#{stage.id}"),
             params: { move_to_stage_id: target.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.stage).to eq(target)
    end

    it 'reorders the stages' do
      stage
      target

      patch kanban_url("boards/#{board.id}/stages/reorder"),
            params: { stage_ids: [target.id, stage.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['stages'].pluck('id')).to eq([target.id, stage.id])
    end
  end

  describe 'cards' do
    let(:board) { create(:flow_kanban_board, account: account) }
    let(:stage) { create(:flow_kanban_stage, board: board) }

    before { create(:inbox_member, inbox: email_inbox, user: agent) }

    it 'creates a card from a conversation of any inbox, for its contact' do
      conversation = conversation_in(email_inbox)

      post kanban_url('cards'), params: { stage_id: stage.id, conversation_id: conversation.display_id },
                                headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      card = response.parsed_body['payload']
      expect(card['contact']['id']).to eq(contact.id)
      expect(card['title']).to eq(contact.name)
      expect(card['conversations']).to eq([{ 'display_id' => conversation.display_id, 'inbox_id' => email_inbox.id,
                                             'status' => 'open', 'last_activity_at' => conversation.last_activity_at.to_i }])
    end

    it 'refuses a conversation the agent cannot see' do
      conversation = conversation_in(api_inbox)

      post kanban_url('cards'), params: { stage_id: stage.id, conversation_id: conversation.display_id },
                                headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'links conversations of other channels to the same card, once per board' do
      card = create(:flow_kanban_card, stage: stage, contact: contact)
      create(:inbox_member, inbox: widget_inbox, user: agent)
      email_conversation = conversation_in(email_inbox)
      widget_conversation = conversation_in(widget_inbox)

      [email_conversation, widget_conversation].each do |conversation|
        post kanban_url("cards/#{card.id}/conversations"), params: { conversation_id: conversation.display_id },
                                                           headers: agent.create_new_auth_token, as: :json
      end
      expect(response.parsed_body['payload']['conversations'].pluck('display_id'))
        .to contain_exactly(email_conversation.display_id, widget_conversation.display_id)

      other_card = create(:flow_kanban_card, stage: stage, contact: contact)
      post kanban_url("cards/#{other_card.id}/conversations"), params: { conversation_id: email_conversation.display_id },
                                                               headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      delete kanban_url("cards/#{card.id}/conversations/#{widget_conversation.display_id}"), headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload']['conversations'].pluck('display_id')).to eq([email_conversation.display_id])
    end

    it 'moves a card between the cards shown around the drop point' do
      target = create(:flow_kanban_stage, board: board)
      above = create(:flow_kanban_card, stage: target, position: 0)
      below = create(:flow_kanban_card, stage: target, position: 1024)
      card = create(:flow_kanban_card, stage: stage)

      patch kanban_url("cards/#{card.id}/move"),
            params: { stage_id: target.id, previous_card_id: above.id, next_card_id: below.id },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(target.cards.ordered).to eq([above, card, below])
    end

    it 'lists each stage with its total and honours the filters' do
      stage
      other_stage = create(:flow_kanban_stage, board: board)
      mine = create(:flow_kanban_card, stage: stage, assignee: agent, title: 'Plano anual')
      create(:flow_kanban_card, stage: stage, title: 'Plano mensal')
      create(:flow_kanban_card, stage: other_stage)
      mine.card_conversations.create!(conversation: conversation_in(email_inbox))

      get kanban_url("boards/#{board.id}/cards"), headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].map { |column| [column['stage_id'], column['total']] })
        .to eq([[stage.id, 2], [other_stage.id, 1]])

      { assignee_id: agent.id, q: 'anual', inbox_id: email_inbox.id }.each do |filter, value|
        get kanban_url("boards/#{board.id}/cards"), params: { filter => value }, headers: agent.create_new_auth_token
        expect(response.parsed_body['payload'].first['cards'].pluck('id')).to eq([mine.id])
      end
    end

    it 'lets only administrators and the card creator delete it' do
      card = create(:flow_kanban_card, stage: stage)

      delete kanban_url("cards/#{card.id}"), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      card.update!(created_by: agent)
      delete kanban_url("cards/#{card.id}"), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'broadcasts card changes to the board audience' do
      card = create(:flow_kanban_card, stage: stage)

      expect do
        patch kanban_url("cards/#{card.id}"), params: { title: 'Renovação' }, headers: agent.create_new_auth_token, as: :json
      end.to have_enqueued_job(ActionCableBroadcastJob).with(
        array_including(agent.pubsub_token), 'kanban.card.updated', hash_including(account_id: account.id)
      )
    end
  end

  describe 'conversation panel' do
    it 'returns the cards a conversation is on and the other cards of its contact' do
      create(:inbox_member, inbox: email_inbox, user: agent)
      conversation = conversation_in(email_inbox)
      stage = create(:flow_kanban_stage, board: create(:flow_kanban_board, account: account))
      linked = create(:flow_kanban_card, stage: stage, contact: contact)
      linked.card_conversations.create!(conversation: conversation)
      suggested = create(:flow_kanban_card, stage: stage, contact: contact)
      hidden_stage = create(:flow_kanban_stage, board: create(:flow_kanban_board, account: account, inboxes: [api_inbox]))
      create(:flow_kanban_card, stage: hidden_stage, contact: contact)

      get kanban_url("conversations/#{conversation.display_id}/cards"), headers: agent.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload['linked'].pluck('id')).to eq([linked.id])
      expect(payload['contact_cards'].pluck('id')).to eq([suggested.id])
      expect(payload['linked'].first['stage']['id']).to eq(stage.id)
    end
  end
end
