require 'rails_helper'

RSpec.describe 'Kanban CSV import and export', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let!(:lead) { create(:flow_kanban_stage, board: board, name: 'Lead', position: 0) }
  let!(:proposal) { create(:flow_kanban_stage, board: board, name: 'Proposta', position: 1) }

  before { ActiveJob::Base.queue_adapter = :test }

  def kanban_url(path)
    "/api/v1/accounts/#{account.id}/kanban/#{path}"
  end

  def upload(csv, kind:, user: admin, **extra)
    file = Rack::Test::UploadedFile.new(StringIO.new(csv), 'text/csv', original_filename: 'file.csv')
    post kanban_url('imports'), params: { file: file, kind: kind }.merge(extra), headers: user.create_new_auth_token
  end

  def analysis
    response.parsed_body['analysis']
  end

  def import_id
    response.parsed_body['payload']['id']
  end

  def run_import(id)
    post kanban_url("imports/#{id}/run"), headers: admin.create_new_auth_token, as: :json
    perform_enqueued_jobs(only: Custom::Kanban::ImportJob)
    Custom::Kanban::Import.find(id)
  end

  describe Custom::Kanban::MoneyParser do
    it 'reads amounts written the Brazilian and the English way' do
      { '1.234,56' => 123_456, '1234.56' => 123_456, 'R$ 10' => 1000, '1,5' => 150, '0,99' => 99, '1.234' => 123_400,
        '1,234.5' => 123_450, '12' => 1200 }.each do |text, cents|
        expect(described_class.cents(text)).to eq(cents), text
      end
    end

    it 'refuses what is not an amount, including negatives' do
      ['abc', '', '-5', '1,234,56,7', '1.2.3,4', '.,', '12abc', 'P-1'].each { |text| expect(described_class.cents(text)).to be_nil, text }
    end

    it 'writes cents as a plain decimal' do
      expect([described_class.decimal(123_456), described_class.decimal(5), described_class.decimal(0)]).to eq(['1234.56', '0.05', '0.00'])
    end
  end

  describe Custom::Kanban::CsvFile do
    it 'reads a UTF-8 file with a BOM and either separator, keeping line numbers' do
      parsed = described_class.parse("﻿nome;preço\nCimento;10,5\n\nAreia;3\n")
      expect(parsed.headers).to eq(%w[nome preço])
      expect(parsed.delimiter).to eq(';')
      expect(parsed.rows.pluck(:line)).to eq([2, 4])
    end

    def parse_code(text)
      described_class.parse(text)
      nil
    rescue described_class::Invalid => e
      e.code
    end

    it 'refuses a file that is too big, too long, empty, malformed or not UTF-8' do
      expect(parse_code('a' * (described_class::MAX_BYTES + 1))).to eq(:too_big)
      expect(parse_code("a\n#{"1\n" * (described_class::MAX_ROWS + 1)}")).to eq(:too_many_rows)
      expect(parse_code("a,b\n")).to eq(:no_rows)
      expect(parse_code("\n\n")).to eq(:empty)
      expect(parse_code("a,b\n\"x,1\n")).to eq(:malformed)
      expect(parse_code("a\n\xFF\n".b)).to eq(:encoding)
    end

    it 'makes a cell that starts like a formula plain text' do
      ['=1+1', '+SUM(A1)', '-2', '@cmd', "\tx", "\rx"].each { |cell| expect(described_class.safe_cell(cell)).to start_with("'") }
      expect([described_class.safe_cell('Cimento'), described_class.safe_cell(12)]).to eq(%w[Cimento 12])
    end
  end

  describe 'exports' do
    it 'exports products as a UTF-8 CSV with a BOM, decimals and no formulas' do
      create(:flow_kanban_product, account: account, name: '=HYPERLINK("http://x")', sku: 'F-1', unit: 'un', price_cents: 123_456)
      create(:flow_kanban_product, account: account, name: 'Cimento', sku: nil, unit: 'sc', price_cents: 3990)

      get kanban_url('products/export'), headers: agent.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.body).to start_with('﻿name,sku,unit,price,active')
      rows = CSV.parse(response.body.delete_prefix('﻿'), headers: true)
      expect(rows.pluck('name')).to contain_exactly("'=HYPERLINK(\"http://x\")", 'Cimento')
      expect(rows.find { |row| row['sku'] == 'F-1' }['price']).to eq('1234.56')
    end

    it 'exports a board’s deals with the filters of the board, in stage order' do
      contact = create(:contact, account: account, name: 'Maria', email: 'maria@example.com', phone_number: '+5511999998888')
      create(:flow_kanban_card, stage: proposal, contact: contact, title: 'Segundo', value_cents: 5000)
      create(:flow_kanban_card, stage: lead, contact: contact, title: 'Primeiro', value_cents: 150_000, assignee: agent)
      create(:flow_kanban_card, stage: lead, title: 'Outro cliente')

      get kanban_url("boards/#{board.id}/cards/export"), params: { q: 'maria' }, headers: agent.create_new_auth_token
      rows = CSV.parse(response.body.delete_prefix('﻿'), headers: true)
      expect(rows.pluck('title')).to eq(%w[Primeiro Segundo])
      expect(rows.first.to_h).to include('stage' => 'Lead', 'value' => '1500.00', 'contact_email' => 'maria@example.com',
                                         'assignee_email' => agent.email)
    end

    it 'does not export a board the person cannot see' do
      restricted = create(:flow_kanban_board, account: account)
      Custom::Kanban::BoardInbox.create!(board: restricted, inbox: create(:inbox, account: account))

      get kanban_url("boards/#{restricted.id}/cards/export"), headers: agent.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      get kanban_url("boards/#{restricted.id}/cards/export"), headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'importing products' do
    let(:csv) { "Nome;Código;Unidade;Preço\nCimento CP II;CIM-1;sc;39,90\nAreia média;AR-1;m3;120\nTijolo;;un;0,85\n" }

    it 'is for administrators only' do
      upload(csv, kind: 'products', user: agent)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'guesses the columns, previews the rows and writes nothing until it runs' do
      upload(csv, kind: 'products')

      expect(response).to have_http_status(:ok)
      mapping = { 'name' => 'Nome', 'sku' => 'Código', 'unit' => 'Unidade', 'price' => 'Preço' }
      expect(response.parsed_body['payload']).to include('mapping' => mapping, 'total_rows' => 3, 'created' => 3, 'errors' => 0)
      expect(analysis['preview'].pluck('action')).to eq(%w[create create create])
      expect(Custom::Kanban::Product.count).to eq(0)
    end

    it 'imports in the background, once, and a second import of the same file changes nothing' do
      upload(csv, kind: 'products')
      done = run_import(import_id)

      expect(done).to have_attributes(status: 'done', created_count: 3, error_count: 0, processed_rows: 3, source: nil)
      expect(Custom::Kanban::Product.where(account: account).pluck(:sku,
                                                                   :price_cents)).to contain_exactly(['CIM-1', 3990], ['AR-1', 12_000], [nil, 85])

      upload(csv, kind: 'products')
      expect(response.parsed_body['payload']).to include('created' => 0, 'updated' => 0, 'skipped' => 3)
      run_import(import_id)
      expect(Custom::Kanban::Product.count).to eq(3)
    end

    it 'updates a product found by SKU and leaves the others alone' do
      create(:flow_kanban_product, account: account, name: 'Cimento velho', sku: 'CIM-1', unit: 'un', price_cents: 100)
      upload(csv, kind: 'products')
      expect(response.parsed_body['payload']).to include('created' => 2, 'updated' => 1)

      run_import(import_id)
      expect(Custom::Kanban::Product.find_by(sku: 'CIM-1')).to have_attributes(name: 'Cimento CP II', price_cents: 3990, unit: 'sc')
    end

    it 'reports every bad row by line, imports the good ones and offers the bad ones as a file' do
      bad = "name,sku,unit,price\nOk,A-1,un,1\n,A-2,un,1\nRuim,A-3,xx,1\nPreço,A-4,un,abc\nRepetido,A-1,un,2\n"
      upload(bad, kind: 'products')

      expect(analysis['errors'].pluck('line')).to eq([3, 4, 5, 6])
      expect(analysis['errors'].first['messages'].first).to be_present
      expect(response.parsed_body['payload']).to include('created' => 1, 'errors' => 4)
      id = import_id

      expect(run_import(id)).to have_attributes(status: 'done', created_count: 1, error_count: 4)
      expect(Custom::Kanban::Product.pluck(:sku)).to eq(['A-1'])

      get kanban_url("imports/#{id}/errors"), headers: admin.create_new_auth_token
      csv_out = CSV.parse(response.body.delete_prefix('﻿'), headers: true)
      expect(csv_out.headers).to eq(%w[line error name sku unit price])
      expect(csv_out.pluck('line')).to eq(%w[3 4 5 6])
    end

    it 'lets the administrator fix the column mapping, then reports again' do
      upload("produto,ref,valor\nParafuso,P-1,2\n", kind: 'products')
      expect(response.parsed_body['payload']['mapping']).to include('name' => 'produto', 'sku' => 'ref', 'price' => 'valor')

      patch kanban_url("imports/#{import_id}"), params: { mapping: { name: 'produto', sku: 'valor', price: 'ref', bogus: 'x' } },
                                                headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload']['mapping']).to eq('name' => 'produto', 'sku' => 'valor', 'price' => 'ref')
      expect(response.parsed_body['payload']['errors']).to eq(1)
    end

    it 'says what is missing when the name column is not mapped' do
      upload("a,b\n1,2\n", kind: 'products')
      expect(analysis['missing']).to eq(['name'])

      post kanban_url("imports/#{import_id}/run"), headers: admin.create_new_auth_token, as: :json
      expect(Custom::Kanban::ImportJob).not_to have_been_enqueued if response.status == 409
    end

    it 'refuses a bad file with a message, and does not start a finished import again' do
      upload("a\n", kind: 'products')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present

      upload(csv, kind: 'products')
      id = import_id
      run_import(id)
      post kanban_url("imports/#{id}/run"), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:conflict)
    end

    it 'only reaches its own account’s imports' do
      upload(csv, kind: 'products')
      other = create(:user, account: create(:account), role: :administrator)
      get "/api/v1/accounts/#{other.account_users.first.account_id}/kanban/imports/#{import_id}", headers: other.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'importing deals' do
    let!(:existing) { create(:contact, account: account, name: 'Maria', email: 'maria@example.com') }
    let(:csv) do
      "title,contact_name,contact_email,contact_phone,stage,value,expected_close_on,assignee_email\n" \
        "Obra Maria,Maria,MARIA@example.com,,Proposta,\"1.500,00\",15/12/2030,#{agent.email}\n" \
        "Obra Joao,João,,(11) 99999-8888,,300,2030-11-01,\n"
    end

    def upload_deals(text = csv)
      upload(text, kind: 'deals', board_id: board.id)
    end

    it 'finds the contact by e-mail, creates the one that is new, and fills the stage from the first open one' do
      upload_deals
      expect(response.parsed_body['payload']).to include('created' => 2, 'errors' => 0)
      expect(Custom::Kanban::Card.count).to eq(0)

      expect(run_import(import_id)).to have_attributes(status: 'done', created_count: 2)

      maria = Custom::Kanban::Card.find_by!(title: 'Obra Maria')
      expect(maria).to have_attributes(contact_id: existing.id, stage_id: proposal.id, value_cents: 150_000, assignee_id: agent.id,
                                       expected_close_on: Date.new(2030, 12, 15), created_by_id: admin.id)
      joao = Custom::Kanban::Card.find_by!(title: 'Obra Joao')
      expect(joao).to have_attributes(stage_id: lead.id, value_cents: 30_000)
      expect(joao.contact).to have_attributes(name: 'João', phone_number: '+11999998888')
      expect(joao.events.pluck(:kind)).to include('created')
    end

    it 'skips a deal that already exists, so importing twice does not double the board' do
      upload_deals
      run_import(import_id)
      upload_deals
      expect(response.parsed_body['payload']).to include('created' => 0, 'skipped' => 2)
      run_import(import_id)
      expect(Custom::Kanban::Card.count).to eq(2)
      expect(account.contacts.where(phone_number: '+11999998888').count).to eq(1)
    end

    it 'explains each kind of bad row' do
      bad = "title,contact_email,contact_phone,stage,value,expected_close_on,assignee_email\n" \
            "A,,,,,,\n" \
            "B,nao-e-email,,,,,\n" \
            "C,c@example.com,,Inexistente,,,\n" \
            "D,d@example.com,,,abc,,\n" \
            "E,e@example.com,,,,31/02/2030,\n" \
            "F,f@example.com,,,,,ninguem@example.com\n" \
            "G,g@example.com,abc,,,,\n" \
            "H,h@example.com,,,,1990-01-01,\n" \
            "I,i@example.com,,,,,\n"
      upload_deals(bad)

      expect(analysis['errors'].pluck('line')).to eq([2, 3, 4, 5, 6, 7, 8, 9])
      expect(response.parsed_body['payload']).to include('created' => 1, 'errors' => 8)
    end

    it 'needs a board the administrator can see' do
      upload(csv, kind: 'deals')
      expect(response).to have_http_status(:unprocessable_entity)

      upload(csv, kind: 'deals', board_id: 0)
      expect(response).to have_http_status(:not_found)
    end

    it 'keeps one bad write from stopping the others' do
      upload_deals
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Custom::Kanban::Importers::Deals).to receive(:apply).and_wrap_original do |original, verdict|
        raise 'boom' if verdict.attrs[:title] == 'Obra Maria'

        original.call(verdict)
      end
      # rubocop:enable RSpec/AnyInstance

      expect(run_import(import_id)).to have_attributes(status: 'done', created_count: 1, error_count: 1)
      expect(Custom::Kanban::Card.pluck(:title)).to eq(['Obra Joao'])
    end
  end

  it 'deletes old imports with the rest of the housekeeping' do
    upload("name\nA\n", kind: 'products')
    Custom::Kanban::Import.update_all(created_at: 8.days.ago) # rubocop:disable Rails/SkipsModelValidations
    Custom::Kanban::NotificationCleanupJob.perform_now
    expect(Custom::Kanban::Import.count).to eq(0)
  end
end
