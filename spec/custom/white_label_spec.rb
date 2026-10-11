require 'rails_helper'

RSpec.describe Custom::WhiteLabel do
  let(:account) { create(:account) }

  def brand!(target = account, **values)
    target.assign_white_label({ 'white_label_enabled' => true }.merge(values.transform_keys { |key| "white_label_#{key}" }))
    target.save!
    target
  end

  def png
    Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')
  end

  def svg
    file = Tempfile.new(%w[logo .svg])
    file.write('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="8"/></svg>')
    file.rewind
    Rack::Test::UploadedFile.new(file.path, 'image/svg+xml')
  end

  describe Account do
    it 'normalizes the domain and rejects a malformed one, a duplicate or a portal domain' do
      brand!(domain: 'HTTPS://Atendimento.Cliente.com.br/login')
      expect(account.white_label_value(:white_label_domain)).to eq('atendimento.cliente.com.br')

      other = create(:account)
      other.assign_white_label('white_label_domain' => 'atendimento.cliente.com.br')
      expect(other).not_to be_valid
      expect(other.errors[:white_label_domain]).to be_present

      other.assign_white_label('white_label_domain' => 'not a domain')
      expect(other).not_to be_valid

      create(:portal, account: other, custom_domain: 'help.cliente.com.br')
      other.assign_white_label('white_label_domain' => 'help.cliente.com.br')
      expect(other).not_to be_valid
    end

    it 'validates colour and links' do
      account.assign_white_label('white_label_color' => 'blue', 'white_label_terms_url' => 'javascript:alert(1)')

      expect(account).not_to be_valid
      expect(account.errors.attribute_names).to include(:white_label_color, :white_label_terms_url)
    end

    it 'refuses an icon that is not PNG or SVG' do
      account.white_label_icon = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')

      expect(account).not_to be_valid
      expect(account.errors[:white_label_icon]).to be_present
    end
  end

  describe Custom::WhiteLabel::Resolver do
    it 'finds an enabled account by its domain, and nothing for the installation host or a disabled one' do
      brand!(domain: 'atendimento.cliente.com.br')

      expect(described_class.account_for_host('Atendimento.Cliente.com.br')).to eq(account)
      expect(described_class.account_for_host(URI.parse(ENV.fetch('FRONTEND_URL', 'http://localhost')).host)).to be_nil

      account.assign_white_label('white_label_enabled' => false)
      account.save!
      expect(described_class.account_for_host('atendimento.cliente.com.br')).to be_nil
    end

    it 'maps the brand onto the installation config keys, leaving unset fields to the installation' do
      account.white_label_icon = png
      brand!(name: 'Clínica Sorriso', color: '#0F766E', powered_by_name: 'Flow Agents')

      config = described_class.new(account).dashboard_config

      expect(config).to include('INSTALLATION_NAME' => 'Clínica Sorriso', 'BRAND_NAME' => 'Flow Agents',
                                'BRAND_COLOR' => '#0F766E', 'DISPLAY_MANIFEST' => false)
      expect(config['LOGO_THUMBNAIL']).to eq("/flow/brand/#{account.id}/white_label_icon/#{account.white_label_icon.blob_id}")
      expect(config).not_to have_key('TERMS_URL')
    end

    it 'gives nothing for an account without a white label' do
      expect(described_class.new(account).dashboard_config).to eq({})
      expect(described_class.new(account).dashboard_payload).to eq(enabled: false)
    end

    it 'adds the accent ramp in the brand colour, and none without a colour' do
      brand!(color: '#0F766E')
      expect(described_class.new(account).dashboard_payload[:theme_css]).to start_with('html:root{--blue-1:').and include('html.dark,html .dark{')

      account.assign_white_label('white_label_color' => '')
      account.save!
      expect(described_class.new(account).dashboard_payload).not_to have_key(:theme_css)
    end
  end

  describe Custom::WhiteLabel::Palette do
    def color(rgb)
      described_class::Color.from_rgb(rgb.split.map(&:to_i))
    end

    it "re-creates Chatwoot's own ramp from Chatwoot's blue" do
      light = described_class.new('#2781F6').variables[:light]

      described_class::REFERENCE[:light].each_with_index do |rgb, index|
        next if index.between?(8, 10) # step 9 is darkened for white text, 10 and 11 follow it

        generated = light["--blue-#{index + 1}"].split.map(&:to_i)
        expect(generated.zip(rgb).map { |a, b| (a - b).abs }.max).to be <= 6
      end
    end

    it 'keeps every contrast promise, whatever the colour' do
      %w[#2414FF #FFC53D #FFFF00 #0B1F44 #000000 #FFFFFF #777777 #E54666 #12A594 #8E4EC6 #2781F6 #00FF66].each do |hex|
        palette = described_class.new(hex)
        light, dark = palette.variables.values_at(:light, :dark)
        white = described_class::WHITE
        page = described_class::Color.from_rgb(described_class::PAGE[:dark])

        expect(color(light['--blue-9']).contrast(white)).to be >= 4.5, "#{hex}: white on light step 9"
        expect(color(dark['--blue-9']).contrast(white)).to be >= 4.5, "#{hex}: white on dark step 9"
        expect(color(light['--blue-11']).contrast(color(light['--blue-3']))).to be >= 4.5, "#{hex}: light accent text"
        expect(color(dark['--blue-11']).contrast(color(dark['--blue-3']))).to be >= 4.5, "#{hex}: dark accent text"
        expect(color(light['--blue-12']).contrast(color(light['--blue-3']))).to be >= 7, "#{hex}: light strong text"
        unless hex == '#000000' # nothing both readable under white text and visible on a near-black page
          expect(color(dark['--blue-9']).contrast(page)).to be >= 3, "#{hex}: dark step 9 on the page"
        end
      end
    end

    it 'uses the brand as it is when white text already reads on it, and says when it had to darken it' do
      expect(described_class.new('#2414FF')).to have_attributes(action_hex: '#2414FF', adjusted?: false)
      expect(described_class.new('#FFC53D').adjusted?).to be(true)
    end

    it 'writes the ramp for both themes, light on :root and dark on the body class the dashboard toggles' do
      css = described_class.new('#0F766E').to_css

      expect(css).to match(/\Ahtml:root\{(--blue-\d+:\d+ \d+ \d+;)+--solid-blue:/)
      expect(css).to include('html.dark,html .dark{', '--border-blue:')
      expect(css).not_to include('<')
    end
  end

  describe Brand do
    it 'lets the white label win over the installation and the account email branding' do
      brand!(name: 'Clínica Sorriso', color: '#0F766E', powered_by_name: 'Flow Agents', powered_by_url: 'https://flow.example')

      brand = described_class.for(account: account)

      expect(brand.name).to eq('Flow Agents')
      expect(brand.url).to eq('https://flow.example')
      expect(brand.color).to eq('#0F766E')
      expect(brand.web_config).to include('INSTALLATION_NAME' => 'Clínica Sorriso', 'BRAND_FROM_ACCOUNT' => true)
    end

    it 'falls back to the brand name when there is no powered-by name' do
      brand!(name: 'Clínica Sorriso')

      expect(described_class.for(account: account).name).to eq('Clínica Sorriso')
    end
  end

  describe 'requests', type: :request do
    it 'renders the dashboard with the account brand on its own domain' do
      brand!(name: 'Clínica Sorriso', domain: 'atendimento.cliente.com.br')

      get '/app/login', headers: { 'HOST' => 'atendimento.cliente.com.br' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<title>', 'Clínica Sorriso')
    end

    it 'inlines the accent ramp on its own domain only' do
      brand!(color: '#0F766E', domain: 'atendimento.cliente.com.br')

      get '/app/login', headers: { 'HOST' => 'atendimento.cliente.com.br' }
      expect(response.body).to include('<style id="flow-white-label-theme">html:root{--blue-1:')

      get '/app/login'
      expect(response.body).not_to include('flow-white-label-theme')
    end

    it 'serves an SVG logo as an image, sandboxed, at a URL that changes with every upload' do
      account.white_label_logo = svg
      brand!

      get account.white_label_image_path(:white_label_logo)

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('image/svg+xml')
      expect(response.headers['Content-Security-Policy']).to include('sandbox', "default-src 'none'")
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.headers['Cache-Control']).to include('public', 'immutable')

      get "/flow/brand/#{account.id}/white_label_logo/#{account.white_label_logo.blob_id + 1}"
      expect(response).to have_http_status(:not_found)

      get "/flow/brand/#{account.id}/avatar/#{account.white_label_logo.blob_id}"
      expect(response).to have_http_status(:not_found)
    end

    it 'shows the images of a disabled white label to a super admin only' do
      account.white_label_icon = png
      brand!
      account.assign_white_label('white_label_enabled' => false)
      account.save!

      get account.white_label_image_path(:white_label_icon)
      expect(response).to have_http_status(:not_found)

      sign_in(create(:super_admin), scope: :super_admin)
      get account.white_label_image_path(:white_label_icon)
      expect(response).to have_http_status(:success)
      expect(response.headers['Cache-Control']).to include('private')
    end

    it 'tells the super admin form what the dashboard makes of a colour' do
      sign_in(create(:super_admin), scope: :super_admin)

      get "/super_admin/accounts/#{account.id}/white_label/palette", params: { color: '#FFC53D' }

      expect(response.parsed_body).to include('adjusted' => true)
      expect(response.parsed_body['white_contrast']).to be < 4.5
      expect(response.parsed_body['ramp'].size).to eq(12)

      get "/super_admin/accounts/#{account.id}/white_label/palette", params: { color: 'yellow' }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'sends the super admin back to the form when the session behind it expired' do
      sign_in(create(:super_admin), scope: :super_admin)
      ActionController::Base.allow_forgery_protection = true

      patch "/super_admin/accounts/#{account.id}/white_label",
            params: { authenticity_token: 'stale', white_label: { white_label_name: 'X' } }

      expect(response).to redirect_to("/super_admin/accounts/#{account.id}/white_label")
      expect(flash[:alert]).to eq(I18n.t('flow_white_label.super_admin.session_expired'))
      expect(account.reload.white_label_value(:white_label_name)).to be_nil
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it 'gives signed-in members the brand to apply after login' do
      brand!(name: 'Clínica Sorriso')
      agent = create(:user, account: account, role: :agent)

      get "/api/v1/accounts/#{account.id}/white_label", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to include('enabled' => true, 'installation_name' => 'Clínica Sorriso')
      expect(response.parsed_body['payload']).not_to have_key('theme_css') # no colour set
    end

    it 'lets only a super admin edit it, and keeps the form on errors' do
      patch "/super_admin/accounts/#{account.id}/white_label", params: { white_label: { white_label_name: 'X' } }
      expect(response).to have_http_status(:redirect)
      expect(account.reload.white_label_value(:white_label_name)).to be_nil

      sign_in(create(:super_admin), scope: :super_admin)
      get "/super_admin/accounts/#{account.id}/white_label"
      expect(response).to have_http_status(:success)

      patch "/super_admin/accounts/#{account.id}/white_label",
            params: { white_label: { white_label_enabled: 'true', white_label_name: 'Clínica Sorriso', white_label_icon: png } }
      expect(response).to redirect_to("/super_admin/accounts/#{account.id}/white_label")
      expect(account.reload).to be_white_label_enabled
      expect(account.white_label_icon).to be_attached

      patch "/super_admin/accounts/#{account.id}/white_label", params: { white_label: { white_label_color: 'azul' } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
