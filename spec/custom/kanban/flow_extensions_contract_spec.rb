require 'rails_helper'

# What the Flow Chatwoot offers beyond the Pro dialect (custom/contracts/flow-extensions.md), proved from the document itself: the
# machine-readable block lists the capabilities the settings must announce and the routes that must exist, and the agents' repository
# checks its toolpack against the same block. The text is byte-identical in both repositories; its hash, with the other contract
# files, is proved in pro_contract_spec.rb.
RSpec.describe 'Flow extensions contract', type: :request do
  let(:document) { Rails.root.join('custom/contracts/flow-extensions.md').read }
  let(:contract) { JSON.parse(document[/```json flow-extensions\n(.*?)\n```/m, 1]) }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'has a machine-readable block' do
    expect(contract['version']).to eq(1)
    expect(contract['routes']).to be_present
  end

  it 'announces exactly the capabilities the contract lists' do
    get "/api/v1/accounts/#{account.id}/kanban/settings", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body.dig('payload', 'capabilities')).to match_array(contract['announced'])
    expect(Api::V1::Accounts::Kanban::SettingsController::CAPABILITIES).to match_array(contract['announced'])
  end

  it 'has a route for every route the contract names, and each one requires an announced capability' do
    contract['routes'].each do |route|
      path = "/api/v1/accounts/#{account.id}#{route['path'].gsub(':display_id', '7').gsub(':product_id', '3')}"

      expect { Rails.application.routes.recognize_path(path, method: route['method']) }
        .not_to raise_error, "#{route['method']} #{route['path']} is in the contract and has no route"
      expect(contract['announced']).to include(route['requires']) if route['requires']
    end
  end
end
