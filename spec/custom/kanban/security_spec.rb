require 'rails_helper'

# A sweep over every Kanban route, so an endpoint added later cannot forget who may call it.
RSpec.describe 'Kanban security sweep', type: :request do
  let(:account) { create(:account) }
  let(:intruder) { create(:user, account: create(:account), role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  # Routes of the Kanban API as [verb, path with :account_id filled and every other id a real or zero id].
  def kanban_routes
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.sub('(.:format)', '')
      next unless path.start_with?('/api/v1/accounts/:account_id/kanban')

      verb = route.verb.to_s[/[A-Z]+/].to_s.downcase
      [verb, path.gsub(':account_id', account.id.to_s).gsub(/:\w+/, '0')]
    end.uniq
  end

  def call(verb, path, user = nil)
    headers = user ? user.create_new_auth_token : {}
    public_send(verb, path, headers: headers, params: {}, as: :json)
  end

  it 'covers the whole Kanban API' do
    expect(kanban_routes.size).to be > 60
  end

  it 'answers 401 to anyone who is not signed in, on every route' do
    answers = kanban_routes.map { |verb, path| [verb, path, call(verb, path) && response.status] }
    expect(answers.reject { |_, _, status| status == 401 }).to eq([])
  end

  it 'answers 401 to an administrator of another account, on every route' do
    answers = kanban_routes.map { |verb, path| [verb, path, call(verb, path, intruder) && response.status] }
    expect(answers.reject { |_, _, status| status == 401 }).to eq([])
  end

  it 'never lets an agent past the administrator-only endpoints, for records that exist' do
    board = create(:flow_kanban_board, account: account)
    stage = create(:flow_kanban_stage, board: board)
    rule = Custom::Kanban::StageAutomation.create!(board: board, trigger_type: 'deal_created',
                                                   actions: [{ 'type' => 'move_to_stage', 'stage_id' => stage.id }])
    webhook = Custom::Kanban::Webhook.create!(account: account, url: 'https://hooks.example.com/x', events: ['deal.won'])
    import = Custom::Kanban::Import.create!(account: account, user: admin, kind: 'products', filename: 'a.csv')
    base = { board: board.id, rule: rule.id, hook: webhook.id, import: import.id }
    paths = {
      'get' => ['webhooks', "boards/#{base[:board]}/automations", "boards/#{base[:board]}/automations/runs",
                "imports/#{base[:import]}", "imports/#{base[:import]}/errors", "webhooks/#{base[:hook]}/deliveries"],
      'post' => ['webhooks', "webhooks/#{base[:hook]}/test", "webhooks/#{base[:hook]}/rotate_secret", 'imports',
                 "imports/#{base[:import]}/run", "boards/#{base[:board]}/automations"],
      'patch' => ["webhooks/#{base[:hook]}", "imports/#{base[:import]}", "boards/#{base[:board]}/automations/#{base[:rule]}"],
      'delete' => ["webhooks/#{base[:hook]}", "boards/#{base[:board]}/automations/#{base[:rule]}"]
    }
    leaks = paths.flat_map do |verb, list|
      list.map { |path| [verb, path, call(verb, "/api/v1/accounts/#{account.id}/kanban/#{path}", agent) && response.status] }
    end
    expect(leaks.reject { |_, _, status| status == 401 }).to eq([])
    expect(webhook.reload.active).to be(true)
    expect(Custom::Kanban::Webhook.where(id: webhook.id)).to exist
  end

  it 'does not serve a signed-in member a server error on any route (a bad id is a 404, not a crash)' do
    crashed = kanban_routes.filter_map do |verb, path|
      call(verb, path, admin)
      [verb, path, response.status] if response.status >= 500
    end
    expect(crashed).to eq([])
  end
end
