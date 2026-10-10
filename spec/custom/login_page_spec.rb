require 'rails_helper'

RSpec.describe Custom::LoginPage do
  def svg
    file = Tempfile.new(%w[logo .svg])
    file.write('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="8"/></svg>')
    file.rewind
    Rack::Test::UploadedFile.new(file.path, 'image/svg+xml')
  end

  def jpg
    Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')
  end

  def live_page(**attributes)
    described_class.create!({ enabled: true, name: 'Flow Agents', accent_color: '#0F766E' }.merge(attributes))
  end

  describe 'validations' do
    it 'accepts the defaults' do
      expect(described_class.new).to be_valid
    end

    it 'refuses an animation that does not suit the background' do
      expect(described_class.new(background_kind: 'brand', animation: 'zoom')).not_to be_valid
      expect(described_class.new(background_kind: 'gradient', animation: 'drift',
                                 gradient: { 'from' => '#111111', 'to' => '#222222', 'angle' => '90' })).to be_valid
    end

    it 'needs two colours and an angle for a gradient, and an image for an image background' do
      expect(described_class.new(background_kind: 'gradient', gradient: { 'from' => '#111111', 'angle' => '90' })).not_to be_valid
      expect(described_class.new(background_kind: 'gradient', gradient: { 'from' => '#111111', 'to' => 'red', 'angle' => '90' })).not_to be_valid
      expect(described_class.new(background_kind: 'image')).not_to be_valid

      page = described_class.new(background_kind: 'image', background_image: jpg)
      expect(page).to be_valid
      page.background_image_removed = true
      expect(page).not_to be_valid
    end

    it 'limits the copy per language and field, and only knows its own languages and fields' do
      expect(described_class.new(copy: { 'pt_BR' => { 'title' => 'x' * 61 } })).not_to be_valid
      expect(described_class.new(copy: { 'pt_BR' => { 'title' => 'x' * 60 } })).to be_valid
      expect(described_class.new(copy: { 'fr' => { 'title' => 'Bonjour' } })).not_to be_valid
      expect(described_class.new(copy: { 'en' => { 'footer' => 'x' } })).not_to be_valid
    end

    it 'takes https and mailto links only' do
      expect(described_class.new(options: { 'support_url' => 'mailto:help@flow.example' })).to be_valid
      expect(described_class.new(options: { 'terms_url' => 'javascript:alert(1)' })).not_to be_valid
    end
  end

  describe 'what the screens get' do
    it 'maps the identity onto the installation config keys, leaving unset ones to Chatwoot' do
      page = live_page(icon: svg)

      expect(page.global_config).to include('INSTALLATION_NAME' => 'Flow Agents', 'BRAND_COLOR' => '#0F766E', 'DISPLAY_MANIFEST' => false)
      expect(page.global_config['LOGO_THUMBNAIL']).to eq("/flow/login/icon/#{page.icon.blob_id}")
      expect(page.global_config).not_to have_key('LOGO')
    end

    it 'gives the layout, background, copy per language and options' do
      page = live_page(layout: 'split', background_kind: 'gradient', animation: 'drift',
                       gradient: { 'from' => '#111111', 'via' => '#333333', 'to' => '#222222', 'angle' => '120' },
                       copy: { 'pt_BR' => { 'title' => 'Bem-vindo' }, 'en' => { 'subtitle' => 'Sign in with your email' } },
                       options: { 'hide_signup' => true, 'support_url' => 'mailto:help@flow.example' })

      payload = page.client_payload

      expect(payload[:layout]).to eq('split')
      expect(payload[:background]).to include(kind: 'gradient', animation: 'drift', css: 'linear-gradient(120deg, #111111, #333333, #222222)')
      expect(payload[:copy]).to eq('pt_BR' => { 'title' => 'Bem-vindo' }, 'en' => { 'subtitle' => 'Sign in with your email' }, 'es' => {})
      expect(payload[:options]).to include('hide_signup' => true, 'hide_sso' => false, 'support_url' => 'mailto:help@flow.example')
    end

    it 'draws the brand aurora from the accent ramp, so it follows the colour and the theme' do
      expect(described_class.new(background_kind: 'brand').background_css).to include('rgb(var(--blue-7))', 'rgb(var(--blue-3))')
    end
  end

  describe 'requests', type: :request do
    it 'wears the login page on the installation host, and nothing when it is off' do
      live_page(copy: { 'pt_BR' => { 'title' => 'Bem-vindo' } })

      get '/app/login'
      expect(response.body).to include('Flow Agents', 'FLOW_LOGIN_PAGE', 'Bem-vindo', '<style id="flow-installation-theme">html:root{--blue-1:')

      described_class.first.update!(enabled: false)
      get '/app/login'
      expect(response.body).not_to include('FLOW_LOGIN_PAGE', 'flow-installation-theme')
    end

    it 'lets an account white label on its own domain win' do
      live_page
      account = create(:account)
      account.assign_white_label('white_label_enabled' => true, 'white_label_name' => 'Clínica Sorriso',
                                 'white_label_domain' => 'atendimento.cliente.com.br')
      account.save!

      get '/app/login', headers: { 'HOST' => 'atendimento.cliente.com.br' }

      expect(response.body).to include('Clínica Sorriso')
      expect(response.body).not_to include('FLOW_LOGIN_PAGE', 'flow-installation-theme')
    end

    it 'serves its images while live, and only to a super admin while off' do
      page = live_page(logo: svg)
      path = page.image_path(:logo)

      get path
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('image/svg+xml')
      expect(response.headers['Content-Security-Policy']).to include('sandbox')

      page.update!(enabled: false)
      get path
      expect(response).to have_http_status(:not_found)

      sign_in(create(:super_admin), scope: :super_admin)
      get path
      expect(response).to have_http_status(:success)
    end

    describe 'Super Admin → Login page' do
      before { sign_in(create(:super_admin), scope: :super_admin) unless RSpec.current_example.metadata[:signed_out] }

      it 'is for super admins only', :signed_out do
        get '/super_admin/login_page'
        expect(response).to have_http_status(:redirect)

        patch '/super_admin/login_page', params: { login_page: { enabled: 'true' } }
        expect(described_class.count).to eq(0)
      end

      it 'shows the form, with its entry in the sidebar' do
        get '/super_admin/login_page'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('data-login-page-form', 'href="http://www.example.com/super_admin/login_page"')
      end

      it 'saves what the form sends, keeping only filled copy and casting the toggles' do
        patch '/super_admin/login_page', params: { login_page: {
          enabled: 'true', name: ' Flow Agents ', accent_color: '#0F766E', layout: 'background',
          background_kind: 'image', animation: 'zoom', overlay: '40', background_image: jpg,
          copy: { pt_BR: { title: 'Bem-vindo', subtitle: '' }, en: { title: '' } },
          options: { hide_signup: 'true', hide_sso: 'false', support_label: 'Ajuda', support_url: 'mailto:help@flow.example' }
        } }

        expect(response).to redirect_to('/super_admin/login_page')
        page = described_class.first
        expect(page).to have_attributes(enabled: true, name: 'Flow Agents', background_kind: 'image', overlay: 40,
                                        copy: { 'pt_BR' => { 'title' => 'Bem-vindo' } })
        expect(page.options).to include('hide_signup' => true, 'hide_sso' => false, 'support_label' => 'Ajuda')
        expect(page.background_image).to be_attached
      end

      it 'keeps the form, with the errors, when something is invalid' do
        patch '/super_admin/login_page', params: { login_page: { accent_color: 'verde' } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(described_class.count).to eq(0)
      end

      it "restores Chatwoot's screens" do
        live_page

        delete '/super_admin/login_page'

        expect(response).to redirect_to('/super_admin/login_page')
        expect(described_class.count).to eq(0)
      end

      it 'previews a colour as the dashboard will show it' do
        get '/super_admin/login_page/palette', params: { color: '#FFC53D' }

        expect(response.parsed_body).to include('adjusted' => true)
        expect(response.parsed_body['ramp_dark'].size).to eq(12)
      end
    end
  end
end
