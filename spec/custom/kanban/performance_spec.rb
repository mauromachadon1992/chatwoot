require 'rails_helper'

# The Kanban endpoints measured: [path, params] from the board.
PERFORMANCE_ENDPOINTS = {
  'the board' => ->(board) { ["boards/#{board.id}/cards", {}] },
  'the board, filtered' => ->(board) { ["boards/#{board.id}/cards", { status: 'stale', q: 'a' }] },
  'my tasks' => ->(_board) { ['tasks', {}] },
  'the report' => ->(board) { ["boards/#{board.id}/report", {}] },
  'the deals export' => ->(board) { ["boards/#{board.id}/cards/export", {}] },
  'the automation runs' => ->(board) { ["boards/#{board.id}/automations/runs", {}] },
  'the boards list' => ->(_board) { ['boards', {}] }
}.freeze

# Seconds each one may take with 10,000 deals.
PERFORMANCE_LIMITS = { 'the board' => 1.5, 'my tasks' => 1.5, 'the report' => 3.0, 'the deals export' => 15.0 }.freeze

# Two guards on how the Kanban scales:
# - a query-count check that runs with the suite: an endpoint must ask the database the same number
#   of questions for 3 deals as for 30, or it has an N+1;
# - a timing run on 10,000 deals, only with PERF=1 (it seeds a lot): `PERF=1 bundle exec rspec
#   spec/custom/kanban/performance_spec.rb`.
RSpec.describe 'Kanban performance', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0, stale_after_days: 3) }
  let!(:won) { create(:flow_kanban_stage, board: board, name: 'Ganho', stage_type: :won, position: 1) }
  let(:inbox) { create(:inbox, account: account) }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def queries_for(path, params = {})
    # The first request of a process pays one-time costs (schema, auth); only the second is counted.
    get kanban_url(path), params: params, headers: admin.create_new_auth_token
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      get kanban_url(path), params: params, headers: admin.create_new_auth_token
    end
    expect(response).to have_http_status(:ok), "#{path}: #{response.status}"
    count
  end

  # A deal with a contact, a conversation, two tasks and a history.
  def add_deal(index)
    card = create(:flow_kanban_card, stage: index.even? ? lead : won, value_cents: 1000 * (index + 1), assignee: admin,
                                     expected_close_on: Date.current + index.days)
    conversation = create(:conversation, account: account, inbox: inbox, contact: card.contact)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: "hello #{index}")
    Custom::Kanban::CardConversation.create!(card: card, conversation: conversation)
    2.times { |n| Custom::Kanban::CardTask.create!(card: card, user: admin, title: "Task #{n}", task_type: 'call', due_at: n.days.from_now) }
    Custom::Kanban::CardEvent.record!(card, 'automation_ran', { automation_id: 1, trigger: 'deal_created', results: [] })
  end

  def add_deals(count)
    count.times { |index| add_deal(index) }
  end

  PERFORMANCE_ENDPOINTS.each do |name, build|
    it "asks the database the same questions for #{name} with 3 deals as with 30" do
      add_deals(3)
      path, params = build.call(board)
      few = queries_for(path, params)
      add_deals(27)
      many = queries_for(path, params)

      expect(many).to be <= few + 1, "#{name}: #{few} queries for 3 deals, #{many} for 30"
    end
  end

  it 'asks the same questions for the product list and export with 3 products as with 30' do
    create_list(:flow_kanban_product, 3, account: account)
    few = [queries_for('products'), queries_for('products/export')]
    create_list(:flow_kanban_product, 27, account: account)
    expect([queries_for('products'), queries_for('products/export')]).to eq(few)
  end

  it 'asks the same questions for the webhook list with 1 webhook as with 8' do
    hook = Custom::Kanban::Webhook.create!(account: account, url: 'https://hooks.example.com/0', events: ['deal.won'])
    hook.deliveries.create!(event: 'ping', payload: {})
    few = queries_for('webhooks')
    7.times do |index|
      other = Custom::Kanban::Webhook.create!(account: account, url: "https://hooks.example.com/#{index + 1}", events: ['deal.won'])
      3.times { other.deliveries.create!(event: 'ping', payload: {}) }
    end
    expect(queries_for('webhooks')).to eq(few)
  end

  describe '10,000 deals', if: ENV['PERF'] == '1' do
    def say(text)
      RSpec.configuration.reporter.message("  #{text}")
    end

    # rubocop:disable Rails/SkipsModelValidations
    before do
      account.update!(flow_kanban_features: [])
      now = Time.current
      contacts = Contact.insert_all(Array.new(10_000) { |i| { account_id: account.id, name: "Contact #{i}", created_at: now, updated_at: now } },
                                    returning: %w[id])
      Custom::Kanban::Card.insert_all(contacts.rows.flatten.each_with_index.map do |contact_id, i|
        { account_id: account.id, board_id: board.id, stage_id: i.even? ? lead.id : won.id, contact_id: contact_id, title: "Deal #{i}",
          position: i, value_cents: 1000 * (i % 50), assignee_id: admin.id, source: 'manual', created_at: now - i.minutes,
          updated_at: now, stage_changed_at: now - (i % 10).days }
      end)
      Custom::Kanban::CardTask.insert_all(Custom::Kanban::Card.where(board: board).limit(5000).pluck(:id).map do |card_id|
        { account_id: account.id, card_id: card_id, user_id: admin.id, title: 'Follow up', task_type: 'call', due_at: now + 1.day,
          created_at: now, updated_at: now }
      end)
    end
    # rubocop:enable Rails/SkipsModelValidations

    PERFORMANCE_LIMITS.each do |name, limit|
      it "serves #{name} in under #{limit} s" do
        path, params = PERFORMANCE_ENDPOINTS.fetch(name).call(board)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        get kanban_url(path), params: params, headers: admin.create_new_auth_token
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        say "#{name}: #{elapsed.round(2)} s, #{response.body.bytesize / 1024} KB"
        expect(response).to have_http_status(:ok)
        expect(elapsed).to be < limit
      end
    end

    it 'finds the stalled deals in under a second' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      count = Custom::Kanban::Card.where(board: board).stale.count
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      say "stalled scan: #{count} deals, #{elapsed.round(2)} s"
      expect(elapsed).to be < 1.0
    end
  end
end
