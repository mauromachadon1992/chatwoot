require 'rails_helper'

# The rest of the Pro dialect (operations 6, 7 and 12 to 14 of custom/contracts/pro-kanban.md): the card's
# priority, dates, labels and attributes, the board's bindings, who made each change, and the webhook payload.
RSpec.describe 'Kanban Pro dialect, fields and bindings', type: :request do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let!(:card) { create(:flow_kanban_card, stage: lead, contact: contact, title: 'Plano Pro', description: 'Antiga') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:service) { create(:user, account: account, role: :administrator, name: 'Agente IA') }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Novo', position: 0) }

  before { create(:flow_kanban_stage, board: board, name: 'Proposta', position: 1) }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def as(user, verb, path, params = {})
    public_send(verb, kanban_url(path), params: params, headers: user.create_new_auth_token, as: :json)
  end

  def patch_task(user: admin, **fields)
    as(user, :patch, "tasks/#{card.id}", task: fields)
  end

  def body
    response.parsed_body
  end

  def task_action(index)
    { 'type' => 'create_task', 'title' => "Tarefa #{index}", 'task_type' => 'call', 'due_in_hours' => 1, 'assignee' => 'deal_agent' }
  end

  def events(kind)
    card.events.where(kind: kind).order(:id)
  end

  describe 'operation 14: title, description, priority and dates' do
    it 'changes only the keys it is sent, and gives them back in the Pro shape' do
      patch_task(title: 'Novo título', priority: 'high', start_date: '2026-10-10T09:00:00-03:00', due_date: '2026-10-30T18:00:00-03:00')

      expect(response).to have_http_status(:ok)
      expect(body).to include('title' => 'Novo título', 'priority' => 'high', 'description' => 'Antiga')
      expect(Time.zone.parse(body['start_date'])).to eq(Time.zone.parse('2026-10-10T12:00:00Z'))
      expect(Time.zone.parse(body['due_date'])).to eq(Time.zone.parse('2026-10-30T21:00:00Z'))
    end

    it 'clears a description, a date and the priority when they are sent as null, and not when they are left out' do
      patch_task(priority: 'low', start_date: '2026-10-10T09:00:00Z', due_date: '2026-10-30T09:00:00Z')
      patch_task(title: 'Só o título')
      expect(body).to include('priority' => 'low')
      expect(body['due_date']).to be_present

      patch_task(description: nil, priority: nil, start_date: nil, due_date: nil)
      expect(body).to include('description' => nil, 'priority' => nil, 'start_date' => nil, 'due_date' => nil, 'title' => 'Só o título')
    end

    it 'takes a plain date, and refuses what is not a date instead of clearing it' do
      patch_task(due_date: '2026-10-30')
      expect(response).to have_http_status(:ok)
      expect(body['due_date']).to start_with('2026-10-30')

      patch_task(due_date: 'next friday')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['message']).to include('ISO 8601')
      expect(card.reload.due_at).to be_present
    end

    it 'refuses an unknown priority, a start after the due date and an empty title' do
      patch_task(priority: 'whenever')
      expect(response).to have_http_status(:unprocessable_entity)

      patch_task(start_date: '2026-11-10T09:00:00Z', due_date: '2026-10-30T09:00:00Z')
      expect(response).to have_http_status(:unprocessable_entity)

      patch_task(title: '')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(card.reload).to have_attributes(title: 'Plano Pro', priority: nil, start_at: nil)
    end

    it 'does not let an agent change a deal of a board they cannot see' do
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))
      patch_task(user: agent, title: 'x')
      expect(response).to have_http_status(:not_found)
      expect(card.reload.title).to eq('Plano Pro')
    end
  end

  describe 'operation 13: labels' do
    it 'replaces the whole set, drops repeats and blanks, and keeps the order' do
      patch_task(labels: %w[vip quente])
      expect(body['labels']).to eq(%w[vip quente])

      patch_task(labels: ['vip', ' vip ', '', 'frio'])
      expect(body['labels']).to eq(%w[vip frio])

      patch_task(labels: [])
      expect(body['labels']).to eq([])
    end

    it 'refuses labels that are not a list of texts, too many, or too long' do
      patch_task(labels: 'vip')
      expect(response).to have_http_status(:unprocessable_entity)
      patch_task(labels: [1, 2])
      expect(response).to have_http_status(:unprocessable_entity)
      patch_task(labels: Array.new(21) { |i| "l#{i}" })
      expect(response).to have_http_status(:unprocessable_entity)
      patch_task(labels: ['a' * 51])
      expect(response).to have_http_status(:unprocessable_entity)
      expect(card.reload.labels).to eq([])
    end
  end

  describe 'operation 12: custom attributes' do
    it 'assigns the whole object (the agents merge before sending), and an empty one clears it' do
      patch_task(custom_attributes: { orcamento: 2000 })
      expect(body['custom_attributes']).to eq('orcamento' => 2000)

      patch_task(custom_attributes: { orcamento: 2000, produto: 'Plano Pro', ativo: true, nested: { a: [1, 2] } })
      expect(body['custom_attributes']).to eq('orcamento' => 2000, 'produto' => 'Plano Pro', 'ativo' => true, 'nested' => { 'a' => [1, 2] })

      patch_task(custom_attributes: {})
      expect(body['custom_attributes']).to eq({})
    end

    it 'refuses what is not an object, too many names, a long name or too much text' do
      patch_task(custom_attributes: 'x')
      expect(response).to have_http_status(:unprocessable_entity)

      patch_task(custom_attributes: Array.new(51) { |i| ["k#{i}", i] }.to_h)
      expect(response).to have_http_status(:unprocessable_entity)

      patch_task(custom_attributes: { ('k' * 61) => 1 })
      expect(response).to have_http_status(:unprocessable_entity)

      patch_task(custom_attributes: { big: 'x' * 10_100 })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(card.reload.custom_attributes).to eq({})
    end
  end

  # The agents' client has no tool for the amount, only the card's attributes: the reserved attribute
  # `deal_value` is how an agent records what it quoted, and the deal's value follows it.
  describe 'the deal value an agent records as the attribute deal_value' do
    it 'sets the value from a typed amount, keeps the attribute, and answers with the value' do
      patch_task(custom_attributes: { deal_value: 'R$ 3.420,00', origem: 'chat' })

      expect(response).to have_http_status(:ok)
      expect(body).to include('value' => 3420.0)
      expect(body['custom_attributes']).to eq('deal_value' => 'R$ 3.420,00', 'origem' => 'chat')
      expect(card.reload.value_cents).to eq(342_000)
    end

    it 'takes a plain number, and records one history event per change, naming the agents\' service user' do
      Custom::Kanban::ServiceUser.mark!(service)
      patch_task(user: service, custom_attributes: { deal_value: 1200 })
      patch_task(user: service, custom_attributes: { deal_value: 1200, origem: 'chat' })
      patch_task(user: service, custom_attributes: { deal_value: '1500.50' })

      expect(card.reload.value_cents).to eq(150_050)
      expect(events('value_changed').map { |event| event.data['to_cents'] }).to eq([120_000, 150_050])
      expect(events('value_changed').last).to have_attributes(actor_kind: 'agent_bot', actor_name: service.name)
    end

    it 'leaves the value alone when the text is not an amount, and never fails the request' do
      card.update!(value_cents: 5_000)
      patch_task(custom_attributes: { deal_value: 'a combinar' })

      expect(response).to have_http_status(:ok)
      expect(card.reload.value_cents).to eq(5_000)
      expect(card.custom_attributes).to eq('deal_value' => 'a combinar')

      patch_task(custom_attributes: { deal_value: '-10' })
      expect(card.reload.value_cents).to eq(5_000)
    end

    it 'leaves the value alone when the deal is worth its products, and when the attribute is not sent' do
      product = create(:flow_kanban_product, account: account, price_cents: 2_000)
      Custom::Kanban::CardItemsService.new(card).add(product: product)
      patch_task(custom_attributes: { deal_value: '9999' })
      expect(response).to have_http_status(:ok)
      expect(card.reload.value_cents).to eq(2_000)

      other = create(:flow_kanban_card, stage: lead, contact: create(:contact, account: account), value_cents: 700)
      as(admin, :patch, "tasks/#{other.id}", task: { custom_attributes: { origem: 'chat' } })
      expect(other.reload.value_cents).to eq(700)
    end

    it 'is announced in the capabilities' do
      as(admin, :get, 'settings')
      expect(body.dig('payload', 'capabilities')).to include('tasks.value_attribute')
    end
  end

  describe 'the dashboard edits the same fields' do
    it 'takes them on PATCH kanban/cards/:id' do
      as(admin, :patch, "cards/#{card.id}", priority: 'urgent', due_at: '2026-10-30T18:00:00Z', labels: ['vip'],
                                            custom_attributes: { origem: 'site' })

      expect(response).to have_http_status(:ok)
      expect(body['payload']).to include('priority' => 'urgent', 'labels' => ['vip'], 'custom_attributes' => { 'origem' => 'site' })
      expect(body['payload']['due_at']).to start_with('2026-10-30')
    end
  end

  describe 'the history says what changed, and who changed it' do
    it 'writes one line per kind of change, with names and never the values of the attributes' do
      Current.user = admin
      card.update!(priority: 'high')
      card.update!(priority: 'low', start_at: Time.zone.parse('2026-10-10'), due_at: Time.zone.parse('2026-10-20'))
      card.update!(labels: %w[vip quente])
      card.update!(labels: %w[vip frio])
      card.update!(custom_attributes: { cpf: '123', origem: 'site' })
      card.update!(custom_attributes: { cpf: '123', origem: 'indicação' })

      expect(events('priority_changed').map(&:data)).to eq([{ 'to' => 'high' }, { 'from' => 'high', 'to' => 'low' }])
      expect(events('dates_changed').last.data).to include('start_at' => '2026-10-10T00:00:00Z', 'due_at' => '2026-10-20T00:00:00Z')
      expect(events('labels_changed').map(&:data)).to eq([{ 'added' => %w[vip quente], 'removed' => [] },
                                                          { 'added' => ['frio'], 'removed' => ['quente'] }])
      expect(events('attributes_changed').map { |event| event.data['keys'] }).to eq([%w[cpf origem], ['origem']])
      expect(card.events.where(kind: 'attributes_changed').to_json).not_to include('123')
    ensure
      Current.reset
    end

    it 'names the actor: a person, the agents\' service user, a rule or the system' do
      Custom::Kanban::ServiceUser.mark!(service)
      patch_task(user: admin, priority: 'high')
      patch_task(user: service, priority: 'low')
      Custom::Kanban::CardEvent.record!(card, 'automation_ran', { automation_id: 1, trigger: 'deal_created', results: [] }, user: nil)
      Custom::Kanban::CardEvent.record!(card, 'quote_prepared', { total_cents: 0 }, user: nil)

      kinds = card.events.order(:id).pluck(:kind, :actor_kind, :actor_name)
      expect(kinds).to include(['priority_changed', 'user', admin.name], ['priority_changed', 'agent_bot', 'Agente IA'],
                               ['automation_ran', 'rule', nil], ['quote_prepared', 'system', nil])
      as(admin, :get, "cards/#{card.id}/events")
      expect(body['payload'].map { |event| event['actor_kind'] }).to include('agent_bot', 'user', 'rule', 'system')
    end

    it 'keeps the actor on the deals a deleted stage hands over' do
      Current.user = admin
      other = create(:flow_kanban_stage, board: board, name: 'Outra', position: 2)
      as(admin, :delete, "boards/#{board.id}/stages/#{lead.id}", move_to_stage_id: other.id)
      expect(card.events.where(kind: 'stage_moved').last).to have_attributes(actor_kind: 'user', actor_name: admin.name)
    ensure
      Current.reset
    end
  end

  describe 'operations 6 and 7: what a board is shared with' do
    it 'shares the board with exactly these inboxes, and sending the same list again changes nothing' do
      inboxes = create_list(:inbox, 2, account: account)
      as(admin, :post, "boards/#{board.id}/update_inboxes", inbox_ids: inboxes.map(&:id))
      expect(response).to have_http_status(:ok)
      expect(board.reload.inbox_ids).to match_array(inboxes.map(&:id))

      expect { as(admin, :post, "boards/#{board.id}/update_inboxes", inbox_ids: inboxes.map(&:id)) }.not_to(change do
        board.reload.board_inboxes.pluck(:id)
      end)

      as(admin, :post, "boards/#{board.id}/update_inboxes", inbox_ids: [inboxes.first.id])
      expect(board.reload.inbox_ids).to eq([inboxes.first.id])
      as(admin, :post, "boards/#{board.id}/update_inboxes", inbox_ids: [])
      expect(board.reload.inbox_ids).to eq([])
    end

    it 'ignores inboxes and agents of another account' do
      stranger = create(:inbox)
      as(admin, :post, "boards/#{board.id}/update_inboxes", inbox_ids: [stranger.id])
      expect(board.reload.inbox_ids).to eq([])

      as(admin, :post, "boards/#{board.id}/update_agents", agent_ids: [create(:user).id])
      expect(board.reload.agent_ids).to eq([])
    end

    it 'shares the board with exactly these agents, and only they (and administrators) see it' do
      other = create(:user, account: account, role: :agent)
      as(admin, :post, "boards/#{board.id}/update_agents", agent_ids: [agent.id])
      expect(response).to have_http_status(:ok)
      expect(body['payload']['agent_ids']).to eq([agent.id])

      expect(Custom::Kanban::Board.visible_to(agent, account)).to include(board)
      expect(Custom::Kanban::Board.visible_to(other, account)).not_to include(board)
      expect(Custom::Kanban::Board.visible_to(admin, account)).to include(board)

      as(other, :get, "boards/#{board.id}/steps")
      expect(response).to have_http_status(:not_found)

      as(admin, :post, "boards/#{board.id}/update_agents", agent_ids: [])
      expect(Custom::Kanban::Board.visible_to(other, account)).to include(board)
    end

    it 'adds agents to the sharing by inbox and team instead of replacing it' do
      inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: inbox)
      other = create(:user, account: account, role: :agent)
      as(admin, :post, "boards/#{board.id}/update_inboxes", inbox_ids: [inbox.id])
      as(admin, :post, "boards/#{board.id}/update_agents", agent_ids: [other.id])

      expect(Custom::Kanban::Board.visible_to(agent, account)).to include(board)
      expect(Custom::Kanban::Board.visible_to(other, account)).to include(board)
      expect(board.reload.member_tokens).to include(agent.pubsub_token, other.pubsub_token)
    end

    it 'is for administrators, and not for the agents\' service user\'s webhooks' do
      as(agent, :post, "boards/#{board.id}/update_agents", agent_ids: [agent.id])
      expect(response).to have_http_status(:unauthorized)
      as(agent, :post, "boards/#{board.id}/update_inboxes", inbox_ids: [])
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'the conversation as a webhook carries its deal' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    before { Custom::Kanban::CardConversation.create!(card: card, conversation: conversation) }

    it 'has kanban_task with the attributes, so the agents need no second call' do
      card.update!(custom_attributes: { orcamento: 2000 }, labels: ['vip'])
      payload = Conversations::EventDataPresenter.new(conversation).webhook_data

      expect(payload[:kanban_task]).to include(id: card.id, labels: ['vip'], custom_attributes: { 'orcamento' => 2000 }, status: 'open')
    end

    it 'reaches the agent bot inside the message event, where the agents read it' do
      card.update!(custom_attributes: { orcamento: 2000 })
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'Olá')

      kanban_task = message.webhook_data[:conversation][:kanban_task]
      expect(kanban_task).to include(id: card.id, custom_attributes: { 'orcamento' => 2000 })
      expect(JSON.parse(message.webhook_data.to_json).dig('conversation', 'kanban_task', 'custom_attributes')).to eq('orcamento' => 2000)
    end

    it 'is nil without an open deal, and is not in what the cable or the contact receive' do
      presenter = Conversations::EventDataPresenter.new(conversation)
      expect(presenter.push_data).not_to have_key(:kanban_task)
      expect(presenter.contact_push_data).not_to have_key(:kanban_task)

      Custom::Kanban::CardConversation.where(card: card).delete_all
      expect(presenter.webhook_data[:kanban_task]).to be_nil
    end
  end

  describe 'rules that feed each other' do
    it 'stop: a deal takes only so many runs an hour' do
      conversation = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: contact)
      Custom::Kanban::CardConversation.create!(card: card, conversation: conversation)
      conversation.update_columns(status: Conversation.statuses[:resolved], status_changed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      stub_const('Custom::Kanban::AutomationRunner::DEAL_RUNS_PER_HOUR', 3)
      Array.new(5) do |index|
        Custom::Kanban::StageAutomation.create!(board: board, trigger_type: 'conversation_status_changed', trigger_config: { 'status' => 'resolved' },
                                                actions: [task_action(index)])
      end
      Custom::Kanban::AutomationRunner.status_changed(conversation.reload)

      expect(Custom::Kanban::AutomationRun.where(card_id: card.id).count).to eq(3)
    end
  end
end
