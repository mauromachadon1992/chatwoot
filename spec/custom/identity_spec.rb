require 'rails_helper'

# The Flow identity (custom/contracts/identity.md) applied to the installation, and the contract's own SVGs it applies.
RSpec.describe Custom::Identity do
  # `LoginPage.current` is the first row, so every example starts from none.
  before { Custom::LoginPage.destroy_all }

  after { Custom::LoginPage.destroy_all }

  describe '.apply!' do
    it 'brands the installation: name, accent, the three images and the copy in each language' do
      page = described_class.apply!

      expect(page).to be_persisted
      expect(page).to have_attributes(enabled: true, name: 'flow-chat', accent_color: '#3E63DD')
      expect([page.logo, page.logo_dark, page.icon]).to all(be_attached)
      expect(page.copy_for('pt_BR', 'title')).to eq('Entrar no flow-chat')
      expect(page.copy_for('en', 'title')).to eq('Sign in to flow-chat')
      expect(page.copy_for('es', 'title')).to eq('Entrar en flow-chat')
    end

    it 'is what the dashboard reads: the installation name, the logos and the accent' do
      config = described_class.apply!.global_config

      expect(config).to include('INSTALLATION_NAME' => 'flow-chat', 'BRAND_COLOR' => '#3E63DD')
      expect(config.values_at('LOGO', 'LOGO_DARK', 'LOGO_THUMBNAIL')).to all(be_present)
      expect(config['LOGO']).not_to eq(config['LOGO_DARK'])
    end

    it 'changes nothing the second time: no new row, no new image' do
      described_class.apply!

      expect { described_class.apply! }.not_to(change { [Custom::LoginPage.count, ActiveStorage::Blob.count] })
    end

    it 'keeps the layout, the options and the copy an administrator set, and only takes the identity' do
      page = Custom::LoginPage.create!(layout: 'split', options: { 'hide_signup' => true }, copy: { 'pt_BR' => { 'panel_message' => 'Bem-vindo' } })

      described_class.apply!

      expect(page.reload).to have_attributes(layout: 'split', name: 'flow-chat')
      expect(page.toggle?(:hide_signup)).to be(true)
      expect(page.copy_for('pt_BR', 'panel_message')).to eq('Bem-vindo')
      expect(page.copy_for('pt_BR', 'title')).to eq('Entrar no flow-chat')
    end

    it 'puts back an image whose file is gone from storage, though its record says it is there' do
      page = described_class.apply!
      blob = page.logo.blob
      blob.service.delete(blob.key)

      described_class.apply!

      expect(page.reload.logo.blob.service.exist?(page.logo.blob.key)).to be(true)
    end

    it 'swaps an image whose bytes differ, and leaves one whose bytes match' do
      page = described_class.apply!
      kept = page.logo.blob.id
      page.icon.attach(io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"/>'), filename: 'old.svg', content_type: 'image/svg+xml')

      described_class.apply!

      expect(page.reload.logo.blob.id).to eq(kept)
      expect(page.icon.filename.to_s).to eq('flow-mark.svg')
    end
  end

  describe '.reset!' do
    it 'goes back to Chatwoot\'s own screens' do
      described_class.apply!

      described_class.reset!

      expect(Custom::LoginPage.count).to eq(0)
      expect(Custom::LoginPage.live).to be_nil
    end
  end

  describe 'the contract\'s files' do
    it 'exist, are SVG, and the lockups name their product' do
      described_class::FILES.each_value do |file|
        path = described_class::DIR.join(file)
        expect(path).to exist
        expect(path.read).to start_with('<svg xmlns="http://www.w3.org/2000/svg"')
      end

      expect(described_class::DIR.join('flow-chat-light.svg').read).to include('aria-label="flow-chat"')
      expect(described_class::DIR.join('flow-chat-dark.svg').read).to include('aria-label="flow-chat"')
      expect(described_class::DIR.join('flow-agents-light.svg').read).to include('aria-label="flow-agents"')
    end

    it 'keep the accent of the identity document the same as the one applied' do
      identity = Rails.root.join('custom/contracts/identity.md').read

      expect(identity).to include(described_class::ACCENT)
      expect(described_class::DIR.join('flow-mark.svg').read.downcase).to include(described_class::ACCENT.downcase)
    end
  end
end
