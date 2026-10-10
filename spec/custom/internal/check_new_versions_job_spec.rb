require 'rails_helper'

RSpec.describe Custom::Internal::CheckNewVersionsJob do
  let(:job) { Internal::CheckNewVersionsJob.new }

  # The CE job runs with DISABLE_ENTERPRISE: the Enterprise job and the plan service do not exist there.
  before { skip 'needs the enterprise edition' unless ChatwootApp.enterprise? }

  before do
    allow(Rails.env).to receive(:production?).and_return(true)
    allow(job).to receive(:fetch_latest_github_release).and_return('4.18.0')
    allow(Internal::ReconcilePlanConfigService).to receive(:new).and_return(instance_double(Internal::ReconcilePlanConfigService, perform: nil))
  end

  it 'runs before the Enterprise job, so the plan reaches it' do
    ancestors = Internal::CheckNewVersionsJob.ancestors
    expect(ancestors.index(described_class)).to be < ancestors.index(Enterprise::Internal::CheckNewVersionsJob)
  end

  it 'stores the plan the Chatwoot Hub has for this installation when the sync is on' do
    allow(ChatwootHub).to receive(:sync_with_hub).and_return('plan' => 'enterprise', 'plan_quantity' => 25)

    with_modified_env(CHATWOOT_HUB_SYNC: 'true') { job.perform }

    expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN').value).to eq('enterprise')
    expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY').value).to eq(25)
  end

  it 'does not call the Hub unless asked to, or with Enterprise off' do
    allow(ChatwootHub).to receive(:sync_with_hub)

    job.perform
    with_modified_env(CHATWOOT_HUB_SYNC: 'false') { job.perform }
    allow(ChatwootApp).to receive(:enterprise?).and_return(false)
    with_modified_env(CHATWOOT_HUB_SYNC: 'true') { job.perform }

    expect(ChatwootHub).not_to have_received(:sync_with_hub)
  end
end
