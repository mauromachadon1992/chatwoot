require 'rails_helper'

RSpec.describe 'Kanban AI summary', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Bruno Agente') }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza') }
  let(:card) { create(:flow_kanban_card, stage: lead, contact: contact, title: 'Obra da Maria', value_cents: 150_000) }
  let(:my_inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:answer) do
    { summary: 'Maria quer cimento para uma obra.', next_task: { title: 'Ligar para a Maria', task_type: 'call', due_in_days: 1 } }.to_json
  end
  let(:sent) { [] }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def payload
    response.parsed_body['payload']
  end

  def ask(user = agent)
    post kanban_url("cards/#{card.id}/ai_summary"), headers: user.create_new_auth_token, as: :json
  end

  def conversation_with(inbox, text)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: text)
    Custom::Kanban::CardConversation.create!(card: card, conversation: conversation)
    conversation
  end

  # The AI call itself is Captain's; here it is replaced by a canned answer that records what it was sent.
  def answer_with(reply)
    allow(Custom::Kanban::DealSummaryService).to receive(:new).and_wrap_original do |original, **args|
      original.call(**args).tap do |service|
        allow(service).to receive(:make_api_call) do |messages:, **|
          sent << messages.pluck(:content).join("\n")
          reply
        end
      end
    end
  end

  before do
    account.update!(flow_kanban_features: ['ai_summary'])
    account.enable_features!('captain_tasks')
    create(:inbox_member, user: agent, inbox: my_inbox)
    answer_with({ message: answer, usage: {} })
  end

  describe 'asking for a draft' do
    it 'returns a summary and a suggested task, and writes nothing to the deal' do
      conversation_with(my_inbox, 'Preciso de 20 sacos de cimento')

      expect { ask }.not_to(change { [card.reload.description, card.tasks.count, card.events.count] })

      expect(response).to have_http_status(:ok)
      expect(payload).to include('summary' => 'Maria quer cimento para uma obra.',
                                 'next_task' => { 'title' => 'Ligar para a Maria', 'task_type' => 'call', 'due_in_days' => 1 },
                                 'used' => { 'conversations' => 1, 'messages' => 1, 'truncated' => false })
      expect(Custom::Kanban::AiDraft.last).to have_attributes(status: 'generated', user_id: agent.id, card_id: card.id)
      expect(Custom::Kanban::AiDraft.last.attributes.values.join).not_to include('cimento')
    end

    it 'sends the deal and only the conversations the agent can open' do
      conversation_with(my_inbox, 'Preciso de 20 sacos de cimento')
      conversation_with(other_inbox, 'Segredo de outra caixa de entrada')
      ask

      expect(sent.first).to include('Obra da Maria', 'Maria Souza', 'Preciso de 20 sacos de cimento')
      expect(sent.first).not_to include('Segredo de outra caixa de entrada')
      expect(payload['used']).to include('conversations' => 1)
    end

    it 'does not send private notes, and sends an administrator everything' do
      conversation = conversation_with(my_inbox, 'Mensagem pública')
      create(:message, conversation: conversation, account: account, inbox: my_inbox, message_type: :outgoing, private: true, content: 'Nota interna')
      conversation_with(other_inbox, 'Conversa de outra caixa')
      ask(admin)

      expect(sent.first).to include('Mensagem pública', 'Conversa de outra caixa')
      expect(sent.first).not_to include('Nota interna')
    end

    it 'keeps the newest messages when a thread is too long, and says so' do
      stub_const('Custom::Kanban::DealSummaryService::MAX_CHARS', 300)
      conversation = conversation_with(my_inbox, 'a' * 100)
      create(:message, conversation: conversation, account: account, inbox: my_inbox, message_type: :incoming, content: 'b' * 150)
      create(:message, conversation: conversation, account: account, inbox: my_inbox, message_type: :incoming, content: "ULTIMA #{'c' * 100}")
      ask

      expect(payload['used']).to include('truncated' => true, 'messages' => 2)
      expect(sent.first).to include('ULTIMA')
      expect(sent.first).not_to include('a' * 100)
    end

    it 'says there is nothing to summarize without calling the assistant' do
      ask
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('nothing_to_summarize')
      expect(sent).to be_empty
      expect(Custom::Kanban::AiDraft.last.status).to eq('failed')
    end

    it 'treats a conversation with no public messages as nothing to summarize' do
      conversation = create(:conversation, account: account, inbox: my_inbox, contact: contact)
      Custom::Kanban::CardConversation.create!(card: card, conversation: conversation)
      ask
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'does not draft for a card of a board the agent cannot see' do
      conversation_with(my_inbox, 'Olá')
      Custom::Kanban::BoardInbox.create!(board: board, inbox: other_inbox)
      ask
      expect(response).to have_http_status(:not_found)
      expect(sent).to be_empty
    end
  end

  describe 'the switch' do
    it 'is off until a super admin turns it on' do
      account.update!(flow_kanban_features: [])
      conversation_with(my_inbox, 'Olá')
      ask
      expect(response).to have_http_status(:forbidden)
      expect(sent).to be_empty
      expect(Custom::Kanban::AiDraft.count).to eq(0)
    end

    it 'is off when Captain tasks are off for the account, whatever the Kanban switch says' do
      account.disable_features!('captain_tasks')
      conversation_with(my_inbox, 'Olá')
      ask
      expect(response).to have_http_status(:forbidden)
      expect(sent).to be_empty
    end

    it 'is not on for an account that never chose' do
      expect(create(:account).flow_kanban_features).not_to include('ai_summary')
    end
  end

  describe 'when the assistant cannot answer' do
    before { conversation_with(my_inbox, 'Olá') }

    it 'says it is not set up when there is no API key' do
      answer_with({ error: 'no key', error_code: 401 })
      ask
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['code']).to eq('not_configured')
    end

    it 'says the quota is used up' do
      answer_with({ error: 'limit', error_code: 429 })
      ask
      expect(response.parsed_body['code']).to eq('quota')
    end

    it 'gives a plain message for any other failure, leaving the card unchanged' do
      answer_with({ error: 'Faraday::TimeoutError: execution expired' })
      expect { ask }.not_to(change { [card.reload.updated_at, card.tasks.count, card.events.count] })

      expect(response).to have_http_status(:bad_gateway)
      expect(response.body).not_to include('Faraday')
      expect(Custom::Kanban::AiDraft.last.status).to eq('failed')
    end
  end

  describe 'reading the answer' do
    before { conversation_with(my_inbox, 'Olá') }

    it 'accepts the model wrapping its JSON in a code fence' do
      answer_with({ message: "```json\n#{answer}\n```", usage: {} })
      ask
      expect(payload).to include('summary' => 'Maria quer cimento para uma obra.')
    end

    it 'uses a plain answer as the summary, with no task' do
      answer_with({ message: 'Resumo em texto simples.', usage: {} })
      ask
      expect(payload).to include('summary' => 'Resumo em texto simples.', 'next_task' => nil)
    end

    it 'repairs a task with a strange type or due date, and drops one without a title' do
      answer_with({ message: { summary: 'ok', next_task: { title: 'Mandar proposta', task_type: 'teleport', due_in_days: 900 } }.to_json, usage: {} })
      ask
      expect(payload['next_task']).to eq('title' => 'Mandar proposta', 'task_type' => 'follow_up', 'due_in_days' => 2)

      answer_with({ message: { summary: 'ok', next_task: { title: '  ', task_type: 'call' } }.to_json, usage: {} })
      ask
      expect(payload['next_task']).to be_nil
    end
  end

  describe 'limits and answers' do
    before { conversation_with(my_inbox, 'Olá') }

    it 'gives an agent ten requests an hour and says when the next one is free' do
      Custom::Kanban::AiDraft::PER_HOUR.times { ask }
      expect(response).to have_http_status(:ok)

      ask
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['code']).to eq('rate_limited')
      expect(response.parsed_body['error']).to match(/\d+ min/)

      ask(admin)
      expect(response).to have_http_status(:ok)
    end

    it 'frees the agent after an hour' do
      Custom::Kanban::AiDraft::PER_HOUR.times { ask }
      Custom::Kanban::AiDraft.update_all(created_at: 61.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      ask
      expect(response).to have_http_status(:ok)
    end

    it 'records what the agent did with a draft, once, and only for their own' do
      ask
      id = payload['draft_id']

      post kanban_url("ai_drafts/#{id}/decide"), params: { decision: 'accepted' }, headers: agent.create_new_auth_token, as: :json
      expect(Custom::Kanban::AiDraft.find(id)).to have_attributes(status: 'accepted')
      expect(Custom::Kanban::AiDraft.find(id).decided_at).to be_present

      post kanban_url("ai_drafts/#{id}/decide"), params: { decision: 'discarded' }, headers: agent.create_new_auth_token, as: :json
      expect(Custom::Kanban::AiDraft.find(id).status).to eq('accepted')

      post kanban_url("ai_drafts/#{id}/decide"), params: { decision: 'accepted' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      post kanban_url("ai_drafts/#{id}/decide"), params: { decision: 'bogus' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'deletes old requests with the rest of the housekeeping' do
      ask
      Custom::Kanban::AiDraft.update_all(created_at: 91.days.ago) # rubocop:disable Rails/SkipsModelValidations
      Custom::Kanban::NotificationCleanupJob.perform_now
      expect(Custom::Kanban::AiDraft.count).to eq(0)
    end
  end
end
