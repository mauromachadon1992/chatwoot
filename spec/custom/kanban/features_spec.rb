require 'rails_helper'

RSpec.describe 'Kanban account features', type: :request do
  let(:account) { create(:account) }

  describe Custom::Kanban::Features do
    it 'gives an account that never chose the defaults: stalled alerts on, automatic deals off' do
      expect(account.flow_kanban_features).to eq(%w[stale_alerts])
      expect(described_class.enabled?(account, :stale_alerts)).to be(true)
      expect(described_class.enabled?(account, :auto_create)).to be(false)
    end

    it 'stores only known features, and an empty choice turns everything off' do
      account.update!(flow_kanban_features: ['auto_create', 'telepathy', ''])
      expect(account.reload.flow_kanban_features).to eq(%w[auto_create])

      account.update!(flow_kanban_features: [''])
      expect(account.reload.flow_kanban_features).to eq([])
      expect(described_class.enabled?(account, :stale_alerts)).to be(false)
    end

    it 'is off for no account' do
      expect(described_class.enabled?(nil, :stale_alerts)).to be(false)
    end
  end

  describe 'Super Admin → Accounts → Edit' do
    let(:super_admin) { create(:super_admin) }

    it 'switches the features without touching the other settings' do
      account.update!(flow_kanban_card_fields: %w[contact value])
      sign_in(super_admin, scope: :super_admin)

      patch "/super_admin/accounts/#{account.id}",
            params: { account: { name: account.name, locale: account.locale, status: account.status,
                                 flow_kanban_features: ['', 'auto_create', 'stale_alerts'] } }

      expect(response).to have_http_status(:redirect)
      expect(account.reload.flow_kanban_features).to eq(%w[auto_create stale_alerts])
      expect(account.flow_kanban_card_fields).to eq(%w[contact value])
    end

    it 'shows each feature with its explanation on the edit page' do
      sign_in(super_admin, scope: :super_admin)

      get "/super_admin/accounts/#{account.id}/edit"

      expect(response.body).to include('Automatic deals', 'Stalled-deal alerts', 'account_flow_kanban_features_auto_create')
    end
  end
end
