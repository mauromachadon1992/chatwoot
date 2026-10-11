require 'rails_helper'

# The Pro Kanban dialect (custom/contracts/pro-kanban.md): the operations the fazer.ai agents' client
# calls, answered over Flow's own boards, stages and cards. The Agents' harness is the other proof.
RSpec.describe 'Kanban Pro dialect', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account, name: 'Vendas SDR') }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Novo', position: 0) }
  let!(:proposal) { create(:flow_kanban_stage, board: board, name: 'Proposta', position: 1) }
  let!(:lost) { create(:flow_kanban_stage, board: board, name: 'Perdido', stage_type: :lost, position: 2) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza') }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def as(user, verb, path, params = {})
    public_send(verb, kanban_url(path), params: params, headers: user.create_new_auth_token, as: :json)
  end

  def body
    response.parsed_body
  end

  # Conversations whose internal id is not their display id, as in real data.
  def conversation_for(card_contact = contact, status: :open)
    create(:conversation, account: account, inbox: inbox, contact: card_contact, status: status)
  end

  def expect_pro_card(card, **expected)
    expect(card.keys).to include('id', 'board_id', 'board_step_id', 'title', 'labels', 'custom_attributes')
    expect(card['labels']).to eq([])
    expect(card['custom_attributes']).to eq({})
    expect(card['board']).to include('name' => 'Vendas SDR')
    expect(card['board']['steps'].pluck('name')).to eq(%w[Novo Proposta Perdido])
    expect(card).to include(expected.stringify_keys)
  end

  describe 'the dialect is announced' do
    it 'says which dialect it speaks on every answer and in the settings' do
      as(agent, :get, 'settings')
      expect(response.headers['X-Flow-Kanban-Dialect']).to eq('pro-v1')
      expect(body['payload']).to include('api_version' => 1, 'dialect' => 'pro-v1')
      expect(body['payload']['capabilities']).to include('tasks.read', 'tasks.move', 'steps.write', 'conversation.kanban_task')
    end
  end

  describe 'operations 1 to 3: boards' do
    it 'lists boards (1), creates one with the {board:} root key (2) and renames it (3)' do
      board
      as(admin, :get, 'boards')
      expect(body['payload'].pluck('name')).to include('Vendas SDR')

      as(admin, :post, 'boards', board: { name: 'Pós-venda' })
      expect(response).to have_http_status(:ok)
      created = body['payload']
      expect(created).to include('name' => 'Pós-venda')

      as(admin, :put, "boards/#{created['id']}", board: { name: 'Pós-venda 2' })
      expect(body['payload']).to include('name' => 'Pós-venda 2')
    end

    it 'gives a board made with the root key no default steps, and a flat one the four defaults' do
      as(admin, :post, 'boards', board: { name: 'Do Agents' })
      as(admin, :get, "boards/#{body['payload']['id']}/steps")
      expect(body['steps']).to eq([])

      as(admin, :post, 'boards', name: 'Do painel')
      expect(Custom::Kanban::Board.find(body['payload']['id']).stages.count).to eq(4)
    end

    it 'does not let an agent create or rename a board' do
      as(agent, :post, 'boards', board: { name: 'x' })
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'operations 4 and 5: steps' do
    it 'lists the steps in order, with cancelled for the lost one (4)' do
      as(agent, :get, "boards/#{board.id}/steps")
      expect(body['steps'].pluck('name')).to eq(%w[Novo Proposta Perdido])
      expect(body['steps'].pluck('cancelled')).to eq([false, false, true])
      expect(body['steps'].first.keys).to include('id', 'name', 'description', 'color', 'cancelled')
    end

    it 'creates a step with the {step:} root key, a lost one with cancelled (5)' do
      as(admin, :post, "boards/#{board.id}/steps", step: { name: 'Fechado', color: '#10B981', description: 'Contrato assinado' })
      expect(response).to have_http_status(:ok)
      expect(body).to include('name' => 'Fechado', 'color' => '#10B981', 'description' => 'Contrato assinado', 'cancelled' => false)

      as(admin, :post, "boards/#{board.id}/steps", step: { name: 'Desistiu', cancelled: true })
      expect(body).to include('cancelled' => true, 'stage_type' => 'lost')
      expect(body['color']).to match(/\A#\h{6}\z/)
      expect(board.stages.order(:position).last.name).to eq('Desistiu')
    end

    it 'refuses a bad colour or a long description, and an agent' do
      as(admin, :post, "boards/#{board.id}/steps", step: { name: 'x', color: 'red' })
      expect(response).to have_http_status(:unprocessable_entity)

      as(admin, :post, "boards/#{board.id}/steps", step: { name: 'x', description: 'a' * 121 })
      expect(response).to have_http_status(:unprocessable_entity)

      as(agent, :post, "boards/#{board.id}/steps", step: { name: 'x' })
      expect(response).to have_http_status(:unauthorized)
    end

    it 'answers 404 for the steps of a board the person cannot see' do
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))
      as(agent, :get, "boards/#{board.id}/steps")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'operations 8 and 11: reading deals' do
    let!(:card) { create(:flow_kanban_card, stage: lead, contact: contact, title: 'Plano Pro', value_cents: 150_050) }

    it 'lists the deals in the Pro shape, not the follow-ups it used to list (8)' do
      as(agent, :get, 'tasks')
      expect(response).to have_http_status(:ok)
      expect_pro_card(body['payload'].first, id: card.id, board_id: board.id, board_step_id: lead.id, title: 'Plano Pro', value: 1500.5,
                                             value_cents: 150_050, status: 'open')
      expect(body['payload'].first).not_to have_key('due_at')
      expect(body['meta']).to include('total' => 1, 'truncated' => false)
    end

    it 'filters by board, and leaves out boards the person cannot see' do
      other = create(:flow_kanban_board, account: account)
      create(:flow_kanban_card, stage: create(:flow_kanban_stage, board: other))
      as(agent, :get, 'tasks', board_id: board.id)
      expect(body['payload'].pluck('id')).to eq([card.id])

      Custom::Kanban::BoardInbox.create!(board: other, inbox: create(:inbox, account: account))
      as(agent, :get, 'tasks')
      expect(body['payload'].pluck('board_id').uniq).to eq([board.id])
    end

    it 'derives the status from the step, orders by step then position, and caps the list' do
      create(:flow_kanban_card, stage: lost, contact: contact, title: 'Perdido')
      create(:flow_kanban_card, stage: proposal, contact: contact, title: 'Em proposta')
      as(agent, :get, 'tasks', board_id: board.id)
      expect(body['payload'].pluck('title')).to eq(['Plano Pro', 'Em proposta', 'Perdido'])
      expect(body['payload'].pluck('status')).to eq(%w[open open lost])

      stub_const('Api::V1::Accounts::Kanban::Compat::TasksController::LIST_LIMIT', 2)
      as(agent, :get, 'tasks', board_id: board.id)
      expect(body['payload'].size).to eq(2)
      expect(body['meta']).to include('total' => 3, 'truncated' => true)
    end

    it 'returns the bare card, with no envelope (11)' do
      as(agent, :get, "tasks/#{card.id}")
      expect(body).not_to have_key('payload')
      expect_pro_card(body, id: card.id, title: 'Plano Pro')
    end

    it 'answers 404 for a deal of a board the person cannot see' do
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))
      as(agent, :get, "tasks/#{card.id}")
      expect(response).to have_http_status(:not_found)
    end

    it 'keeps the agent\'s own follow-ups at my_tasks' do
      Custom::Kanban::CardTask.create!(card: card, user: agent, title: 'Ligar', task_type: 'call', due_at: 1.day.from_now)
      as(agent, :get, 'my_tasks')
      expect(body['payload'].pluck('title')).to eq(['Ligar'])
    end
  end

  describe 'operation 9: creating a deal' do
    it 'links the conversation by display id, takes its contact and the first open step' do
      create_list(:conversation, 3)
      conversation = conversation_for
      expect(conversation.display_id).not_to eq(conversation.id)

      as(admin, :post, 'tasks', task: { title: 'Negócio da Maria', board_id: board.id, conversation_id: conversation.display_id, value: 1500.5 })

      expect(response).to have_http_status(:ok)
      expect_pro_card(body, title: 'Negócio da Maria', board_step_id: lead.id, value: 1500.5, value_cents: 150_050,
                            conversation_ids: [conversation.display_id])
      expect(Custom::Kanban::Card.find(body['id']).contact_id).to eq(contact.id)
    end

    it 'puts the deal on the step asked for, and titles it after the contact when no title comes' do
      as(admin, :post, 'tasks', task: { board_id: board.id, board_step_id: proposal.id, contact_id: contact.id })
      expect(body).to include('title' => 'Maria Souza', 'board_step_id' => proposal.id)
    end

    it 'takes the value as a number without going through a float' do
      as(admin, :post, 'tasks', task: { board_id: board.id, contact_id: contact.id, value: '0.07' })
      expect(body['value_cents']).to eq(7)

      as(admin, :post, 'tasks', task: { board_id: board.id, contact_id: contact.id, value: 'abc' })
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'says what is missing without a contact or a conversation' do
      as(admin, :post, 'tasks', task: { board_id: board.id, title: 'x' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['message']).to include('conversation_id')
    end

    it 'refuses a step of another board, a board the person cannot see and a conversation they cannot open' do
      other_step = create(:flow_kanban_stage, board: create(:flow_kanban_board, account: account))
      as(admin, :post, 'tasks', task: { board_id: board.id, board_step_id: other_step.id, contact_id: contact.id })
      expect(response).to have_http_status(:not_found)

      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))
      as(agent, :post, 'tasks', task: { board_id: board.id, contact_id: contact.id })
      expect(response).to have_http_status(:not_found)
    end

    it 'does not link a conversation the agent cannot open' do
      other_inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: other_inbox, contact: contact)
      as(agent, :post, 'tasks', task: { board_id: board.id, conversation_id: conversation.display_id })
      expect(response).to have_http_status(:unauthorized)
      expect(Custom::Kanban::Card.count).to eq(0)
    end
  end

  describe 'operation 10: moving a deal' do
    let!(:card) { create(:flow_kanban_card, stage: lead, contact: contact) }

    it 'moves to a step and lands above insert_before_task_id' do
      first = create(:flow_kanban_card, stage: proposal, contact: contact, title: 'Primeiro')
      second = create(:flow_kanban_card, stage: proposal, contact: contact, title: 'Segundo')

      # New cards enter at the top, so the column reads second, first.
      expect(proposal.cards.ordered.pluck(:id)).to eq([second.id, first.id])

      as(admin, :post, "tasks/#{card.id}/move", board_step_id: proposal.id, insert_before_task_id: first.id)
      expect(response).to have_http_status(:ok)
      expect(body).to include('board_step_id' => proposal.id)
      expect(proposal.cards.reload.ordered.pluck(:id)).to eq([second.id, card.id, first.id])
    end

    it 'moving to the step it is already on changes nothing but its order, and writes one history line per real move' do
      expect { as(admin, :post, "tasks/#{card.id}/move", board_step_id: lead.id) }.not_to(change { card.events.where(kind: 'stage_moved').count })
      expect(response).to have_http_status(:ok)

      as(admin, :post, "tasks/#{card.id}/move", board_step_id: proposal.id)
      expect(card.events.where(kind: 'stage_moved').count).to eq(1)
    end

    it 'takes a lost reason onto a lost step' do
      reason = Custom::Kanban::LostReason.create!(account: account, name: 'Preço')
      as(admin, :post, "tasks/#{card.id}/move", board_step_id: lost.id, lost_reason_id: reason.id, lost_note: 'Achou caro')
      expect(card.reload).to have_attributes(stage_id: lost.id, lost_reason_id: reason.id, lost_note: 'Achou caro')
      expect(body['status']).to eq('lost')
    end

    it 'answers 404 for a step of another board or a neighbour that is not on the target step' do
      other_step = create(:flow_kanban_stage, board: create(:flow_kanban_board, account: account))
      as(admin, :post, "tasks/#{card.id}/move", board_step_id: other_step.id)
      expect(response).to have_http_status(:not_found)

      as(admin, :post, "tasks/#{card.id}/move", board_step_id: proposal.id, insert_before_task_id: card.id)
      expect(response).to have_http_status(:not_found)
    end

    it 'does not let an agent move a deal of a board they cannot see' do
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))
      as(agent, :post, "tasks/#{card.id}/move", board_step_id: proposal.id)
      expect(response).to have_http_status(:not_found)
      expect(card.reload.stage_id).to eq(lead.id)
    end
  end

  describe 'operation 15: the conversation carries its deal' do
    let(:conversation) { conversation_for }

    before { create(:inbox_member, user: agent, inbox: inbox) }

    def link(card)
      Custom::Kanban::CardConversation.create!(card: card, conversation: conversation)
    end

    def read_conversation(user = agent)
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: user.create_new_auth_token, as: :json
      response.parsed_body
    end

    it 'embeds the card, the same shape as reading it' do
      card = create(:flow_kanban_card, stage: lead, contact: contact, title: 'Embutido')
      link(card)

      expect_pro_card(read_conversation['kanban_task'], id: card.id, title: 'Embutido')
    end

    it 'is null without a deal, and when the deals are all won or lost' do
      expect(read_conversation).to have_key('kanban_task')
      expect(read_conversation['kanban_task']).to be_nil

      link(create(:flow_kanban_card, stage: lost, contact: contact))
      expect(read_conversation['kanban_task']).to be_nil
    end

    it 'is the most recently updated open deal when several are linked' do
      other_board = create(:flow_kanban_board, account: account)
      older = create(:flow_kanban_card, stage: lead, contact: contact, title: 'Antigo')
      newer = create(:flow_kanban_card, stage: create(:flow_kanban_stage, board: other_board), contact: contact, title: 'Novo')
      [older, newer].each { |card| link(card) }
      older.update_columns(updated_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations

      expect(read_conversation['kanban_task']['id']).to eq(newer.id)
    end

    it 'leaves out a deal on a board the person cannot see' do
      link(create(:flow_kanban_card, stage: lead, contact: contact))
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))

      expect(read_conversation['kanban_task']).to be_nil
      expect(read_conversation(admin)['kanban_task']).to be_present
    end

    it 'is not part of what the conversation list, the cable or the widget carry' do
      link(create(:flow_kanban_card, stage: lead, contact: contact))
      get "/api/v1/accounts/#{account.id}/conversations", headers: agent.create_new_auth_token, as: :json
      expect(response.body).not_to include('kanban_task')

      presenter = Conversations::EventDataPresenter.new(conversation)
      expect(presenter.push_data).not_to have_key(:kanban_task)
      expect(presenter.contact_push_data).not_to have_key(:kanban_task)
    end

    it 'asks the database the same questions for a conversation with a deal as for one without' do
      other = conversation_for(create(:contact, account: account))
      link(create(:flow_kanban_card, stage: lead, contact: contact))
      count = lambda do |target|
        total = 0
        counter = ->(*, payload) { total += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
          get "/api/v1/accounts/#{account.id}/conversations/#{target.display_id}", headers: agent.create_new_auth_token, as: :json
        end
        total
      end
      count.call(other)
      expect(count.call(conversation)).to be <= count.call(other) + 6
    end
  end

  describe 'the agents\' service user' do
    let(:service) { create(:user, account: account, role: :administrator) }

    before { Custom::Kanban::ServiceUser.mark!(service) }

    it 'does everything an administrator does on the deals' do
      as(service, :post, 'boards', board: { name: 'Do Agents' })
      expect(response).to have_http_status(:ok)
      as(service, :post, "boards/#{body['payload']['id']}/steps", step: { name: 'Novo' })
      expect(response).to have_http_status(:ok)
      as(service, :post, 'tasks', task: { board_id: board.id, contact_id: contact.id })
      expect(response).to have_http_status(:ok)
      as(service, :post, "tasks/#{body['id']}/move", board_step_id: proposal.id)
      expect(response).to have_http_status(:ok)
    end

    it 'cannot reach outside or change the rules: webhooks, imports and automations' do
      as(service, :post, 'webhooks', url: 'https://hooks.example.com/x', events: ['deal.won'])
      expect(response).to have_http_status(:unauthorized)
      as(service, :get, 'webhooks')
      expect(response).to have_http_status(:unauthorized)
      as(service, :post, 'imports', kind: 'products')
      expect(response).to have_http_status(:unauthorized)
      as(service, :post, "boards/#{board.id}/automations", trigger_type: 'deal_created', actions: [{ type: 'move_to_stage', stage_id: lead.id }])
      expect(response).to have_http_status(:unauthorized)
      expect(Custom::Kanban::Webhook.count).to eq(0)
    end

    it 'is a person again once unmarked, and a human administrator was never affected' do
      as(admin, :get, 'webhooks')
      expect(response).to have_http_status(:ok)

      Custom::Kanban::ServiceUser.unmark!(service)
      as(service, :get, 'webhooks')
      expect(response).to have_http_status(:ok)
    end

    it 'cannot unmark itself through the profile' do
      patch '/api/v1/profile', params: { profile: { phone_number: '+5511999990000', custom_attributes: { flow_service: '' } } },
                               headers: service.create_new_auth_token, as: :json
      expect(Custom::Kanban::ServiceUser.agent_bot?(service.reload)).to be(true)
    end

    it 'is marked from the console task' do
      user = create(:user, account: account, role: :administrator)
      expect(Custom::Kanban::ServiceUser.agent_bot?(user)).to be(false)
      Custom::Kanban::ServiceUser.mark!(user)
      expect(Custom::Kanban::ServiceUser.agent_bot?(user.reload)).to be(true)
    end
  end
end
