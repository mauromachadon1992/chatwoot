require 'rails_helper'

# The fork's own release is public, like /api: a monitor tells which build answers without signing in.
RSpec.describe FlowVersionController, type: :request do
  it 'answers without a session, with the fork release, Chatwoot version and revision' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('FLOW_VERSION').and_return('0.1.0')

    get '/flow/version'

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('product' => 'flow-chat', 'version' => '0.1.0', 'chatwoot_version' => Chatwoot.config[:version])
    expect(response.parsed_body).to have_key('revision')
  end

  it 'says null for a build that carries no fork release' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('FLOW_VERSION').and_return(nil)

    get '/flow/version'

    expect(response.parsed_body['version']).to be_nil
  end
end
