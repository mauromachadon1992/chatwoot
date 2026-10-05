require 'rails_helper'

RSpec.describe Custom::EnterpriseDev do
  let!(:account) { create(:account) }

  it 'turns on the enterprise plan and every feature but the internal and deprecated ones' do
    described_class.new.enable(seats: 10)

    expect(ChatwootHub.pricing_plan).to eq('enterprise')
    expect(ChatwootHub.pricing_plan_quantity).to eq(10)
    expect(account.reload.enabled_features.keys).to include(*described_class.features)
    expect(described_class.features).to include('audit_logs', 'custom_roles', 'sla', 'captain_integration', 'saml')
    expect(described_class.skipped_features).to include('search_with_gin', 'inbox_view')
  end

  it 'goes back to what an unlicensed installation sees' do
    described_class.new.enable
    described_class.new.disable

    expect(ChatwootHub.pricing_plan).to eq('community')
    expect(account.reload.feature_enabled?('audit_logs')).to be(false)
  end

  it 'refuses to run in production' do
    allow(Rails.env).to receive(:local?).and_return(false)

    expect { described_class.new }.to raise_error(described_class::NotAllowed)
  end
end
