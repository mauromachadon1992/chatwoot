require 'rails_helper'

RSpec.describe 'Kanban webhooks', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let!(:won) { create(:flow_kanban_stage, board: board, name: 'Ganho', stage_type: :won, position: 1) }
  let!(:lost) { create(:flow_kanban_stage, board: board, name: 'Perdido', stage_type: :lost, position: 2) }
  let(:url) { 'https://hooks.example.com/flow' }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def payload
    response.parsed_body['payload']
  end

  def hook(attributes = {})
    Custom::Kanban::Webhook.create!({ account: account, url: url, events: Custom::Kanban::Webhook::EVENTS }.merge(attributes))
  end

  def deliveries(event = nil)
    scope = Custom::Kanban::WebhookDelivery.order(:id)
    event ? scope.where(event: event) : scope
  end

  before do
    allow(Resolv).to receive(:getaddresses).with('hooks.example.com').and_return(['93.184.216.34'])
    stub_request(:post, url).to_return(status: 200, body: 'ok')
  end

  describe 'the API' do
    it 'is for administrators only' do
      hook
      get kanban_url('webhooks'), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post kanban_url('webhooks'), params: { url: url, events: ['deal.created'] }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'shows the secret once, on creation, and never again' do
      post kanban_url('webhooks'), params: { url: url, events: ['deal.created', 'deal.won'] },
                                   headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      secret = response.parsed_body['secret']
      expect(secret).to match(/\A\h{48}\z/)
      expect(payload).not_to have_key('secret')

      get kanban_url('webhooks'), headers: admin.create_new_auth_token, as: :json
      expect(response.body).not_to include(secret)
      expect(payload.first).to include('url' => url, 'events' => ['deal.created', 'deal.won'], 'active' => true)
      expect(response.parsed_body['meta']['events']).to eq(Custom::Kanban::Webhook::EVENTS)
    end

    it 'refuses an address that is not https, has no events, or is the eleventh' do
      ['http://hooks.example.com/x', 'ftp://hooks.example.com', 'not a url', 'https://user:pass@hooks.example.com/'].each do |bad|
        post kanban_url('webhooks'), params: { url: bad, events: ['deal.created'] }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity), bad
      end

      post kanban_url('webhooks'), params: { url: url, events: ['made.up'] }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      10.times { |index| hook(url: "https://hooks.example.com/#{index}") }
      post kanban_url('webhooks'), params: { url: url, events: ['deal.created'] }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'updates, turns off and deletes, and only reaches its own account' do
      mine = hook
      other = Custom::Kanban::Webhook.create!(account: create(:account), url: url, events: ['deal.created'])

      patch kanban_url("webhooks/#{mine.id}"), params: { active: false, events: ['deal.lost'] }, headers: admin.create_new_auth_token, as: :json
      expect(payload).to include('active' => false, 'events' => ['deal.lost'])

      patch kanban_url("webhooks/#{other.id}"), params: { active: false }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      delete kanban_url("webhooks/#{mine.id}"), headers: admin.create_new_auth_token, as: :json
      expect(Custom::Kanban::Webhook.where(id: mine.id)).to be_empty
    end

    it 'lists the last deliveries with the newest first' do
      webhook = hook
      create_list(:flow_kanban_card, 2, stage: lead)
      get kanban_url("webhooks/#{webhook.id}/deliveries"), headers: admin.create_new_auth_token, as: :json
      expect(payload.pluck('event')).to eq(['deal.created', 'deal.created'])
      expect(payload.first['id']).to be > payload.last['id']
    end
  end

  describe 'sending a test' do
    it 'sends a signed ping now and reports the answer' do
      webhook = hook
      post kanban_url("webhooks/#{webhook.id}/test"), headers: admin.create_new_auth_token, as: :json

      expect(payload).to include('event' => 'ping', 'status' => 'success', 'http_status' => 200, 'attempts' => 1)
      expect(WebMock).to(have_requested(:post, url).with do |request|
        timestamp, digest = request.headers['X-Flow-Signature'].match(/t=(\d+),v1=(\h+)/).captures
        digest == OpenSSL::HMAC.hexdigest('SHA256', webhook.secret, "#{timestamp}.#{request.body}") &&
          request.headers['X-Flow-Event'] == 'ping' && JSON.parse(request.body)['event'] == 'ping'
      end)
    end

    it 'reports a receiver that says no, without retrying' do
      stub_request(:post, url).to_return(status: 404)
      post kanban_url("webhooks/#{hook.id}/test"), headers: admin.create_new_auth_token, as: :json
      expect(payload).to include('status' => 'failed', 'http_status' => 404, 'error' => 'HTTP 404')
    end
  end

  describe 'events' do
    include ActiveJob::TestHelper

    before do
      ActiveJob::Base.queue_adapter = :test
      hook
    end

    let(:card) { create(:flow_kanban_card, stage: lead, value_cents: 1000) }

    it 'queues a delivery for a deal created, with the deal as it was' do
      card
      delivery = deliveries('deal.created').last
      expect(delivery.status).to eq('pending')
      expect(delivery.payload).to include('event' => 'deal.created', 'account_id' => account.id)
      expect(delivery.payload['deal']).to include('id' => card.id, 'title' => card.title, 'value_cents' => 1000,
                                                  'stage' => { 'id' => lead.id, 'name' => 'Lead', 'type' => 'open' })
      expect(Custom::Kanban::WebhookDeliveryJob).to have_been_enqueued.with(delivery.id)
    end

    it 'says moved, and also won or lost when the stage is one' do
      card
      card.move_to!(stage: won)
      expect(deliveries.pluck(:event)).to include('deal.moved', 'deal.won')
      expect(deliveries('deal.lost')).to be_empty

      card.move_to!(stage: lost)
      expect(deliveries('deal.lost').count).to eq(1)
    end

    it 'says the value changed and a task was created' do
      card
      card.update!(value_cents: 2500)
      expect(deliveries('deal.value_changed').last.payload['data']).to include('from_cents' => 1000, 'to_cents' => 2500)

      Custom::Kanban::CardEvent.record!(card, 'task_created', { title: 'Ligar' })
      expect(deliveries('task.created').last.payload['data']).to include('title' => 'Ligar')
    end

    it 'only tells webhooks that listen, are on and belong to the account' do
      hook(events: ['deal.lost'], url: 'https://hooks.example.com/lost')
      hook(active: false, url: 'https://hooks.example.com/off')
      Custom::Kanban::Webhook.create!(account: create(:account), url: url, events: ['deal.created'])
      card

      expect(deliveries('deal.created').map { |delivery| delivery.webhook.url }).to eq([url])
    end

    it 'sends nothing when the account turned webhooks off' do
      account.update!(flow_kanban_features: [])
      card
      expect(deliveries).to be_empty
    end

    it 'sends nothing for a change that was rolled back' do
      ActiveRecord::Base.transaction do
        card
        raise ActiveRecord::Rollback
      end
      expect(deliveries).to be_empty
    end
  end

  describe 'delivery' do
    let(:webhook) { hook }
    let(:delivery) { webhook.deliveries.create!(event: 'deal.created', payload: { event: 'deal.created' }) }

    it 'marks a delivery as succeeded' do
      Custom::Kanban::WebhookDeliveryJob.perform_now(delivery.id)
      expect(delivery.reload).to have_attributes(status: 'success', attempts: 1, http_status: 200, error: nil)
      expect(delivery.delivered_at).to be_present
    end

    it 'retries a busy receiver with a growing wait, then gives up after five tries' do
      stub_request(:post, url).to_return(status: 503)
      waits = []
      allow(Custom::Kanban::WebhookDeliveryJob).to receive(:set) { |options|
        waits << options[:wait]
        instance_double(ActiveJob::ConfiguredJob, perform_later: true)
      }

      5.times { Custom::Kanban::WebhookDeliveryJob.perform_now(delivery.id) }

      expect(waits).to eq([1.minute, 5.minutes, 30.minutes, 2.hours])
      expect(delivery.reload).to have_attributes(status: 'failed', attempts: 5, http_status: 503)
    end

    it 'does not retry a client error and leaves a finished delivery alone' do
      stub_request(:post, url).to_return(status: 400)
      Custom::Kanban::WebhookDeliveryJob.perform_now(delivery.id)
      expect(delivery.reload).to have_attributes(status: 'failed', attempts: 1)

      Custom::Kanban::WebhookDeliveryJob.perform_now(delivery.id)
      expect(delivery.reload.attempts).to eq(1)
    end

    it 'retries a timeout and keeps the error short' do
      stub_request(:post, url).to_timeout
      allow(Custom::Kanban::WebhookDeliveryJob).to receive(:set).and_return(instance_double(ActiveJob::ConfiguredJob, perform_later: true))
      Custom::Kanban::WebhookDeliveryJob.perform_now(delivery.id)
      expect(delivery.reload).to have_attributes(status: 'retrying', attempts: 1)
      expect(delivery.error.length).to be <= Custom::Kanban::WebhookSender::ERROR_MAX_LENGTH
    end

    it 'does not send for a webhook turned off meanwhile' do
      delivery
      webhook.update!(active: false)
      Custom::Kanban::WebhookDeliveryJob.perform_now(delivery.id)
      expect(delivery.reload).to have_attributes(status: 'failed', attempts: 0, error: 'webhook_off')
      expect(WebMock).not_to have_requested(:post, url)
    end

    it 'never connects to a private, local or unresolvable address' do
      %w[127.0.0.1 10.0.0.5 192.168.1.9 169.254.169.254 ::1 ::ffff:127.0.0.1].each do |ip|
        allow(Resolv).to receive(:getaddresses).with('hooks.example.com').and_return([ip])
        result = Custom::Kanban::WebhookSender.new(webhook, delivery).call
        expect(result.error).to eq('blocked_address'), ip
        expect(result.retryable).to be(false)
      end

      allow(Resolv).to receive(:getaddresses).with('hooks.example.com').and_return([])
      expect(Custom::Kanban::WebhookSender.new(webhook, delivery).call.error).to eq('unresolved_host')
      expect(WebMock).not_to have_requested(:post, url)
    end

    it 'deletes old deliveries with the rest of the housekeeping' do
      old = webhook.deliveries.create!(event: 'ping', payload: {}, created_at: 31.days.ago)
      fresh = webhook.deliveries.create!(event: 'ping', payload: {})
      Custom::Kanban::NotificationCleanupJob.perform_now
      expect(Custom::Kanban::WebhookDelivery.where(id: [old.id, fresh.id])).to contain_exactly(fresh)
    end

    it 'keeps the log when the deal is deleted and drops it with the webhook' do
      card = create(:flow_kanban_card, stage: lead)
      webhook.deliveries.create!(event: 'deal.created', card_id: card.id, payload: {})
      card.destroy!
      expect(webhook.deliveries.count).to eq(1)

      webhook.destroy!
      expect(Custom::Kanban::WebhookDelivery.count).to eq(0)
    end
  end
end
