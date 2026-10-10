require 'rails_helper'

RSpec.describe 'Kanban my tasks', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account, name: 'Vendas') }
  let(:stage) { create(:flow_kanban_stage, board: board) }
  let(:card) { create(:flow_kanban_card, stage: stage, title: 'Obra da Maria') }
  let(:now) { Time.zone.parse('2026-10-07 14:00:00') }

  around { |example| travel_to(now) { example.run } }

  def task(**attributes)
    Custom::Kanban::CardTask.create!({ card: card, user: agent, title: 'Ligar', task_type: 'call', due_at: now + 1.day }.merge(attributes))
  end

  def tasks_url(params = {})
    "/api/v1/accounts/#{account.id}/kanban/my_tasks?#{params.to_query}"
  end

  def payload
    response.parsed_body['payload']
  end

  def meta
    response.parsed_body['meta']
  end

  it 'lists the agent’s own open tasks by due date, with the deal and its board' do
    later = task(title: 'Enviar planta', due_at: now + 2.days)
    sooner = task(title: 'Ligar', due_at: now - 1.hour)
    task(user: admin, title: 'Do admin')
    task(title: 'Feita', completed_at: now - 1.hour)

    get tasks_url, headers: agent.create_new_auth_token, as: :json

    expect(payload.pluck('id')).to eq([sooner.id, later.id])
    expect(payload.first['card']).to eq('id' => card.id, 'title' => 'Obra da Maria', 'board_id' => board.id, 'board_name' => 'Vendas')
    expect(payload.first['overdue']).to be(true)
    expect(meta).to include('open_count' => 2, 'overdue_count' => 1, 'has_more' => false, 'page' => 1)
  end

  it 'counts today’s tasks up to the end of the viewer’s day, and ignores a nonsense end' do
    task(due_at: now + 3.hours)
    task(due_at: now + 1.day)

    get tasks_url(today_ends_at: (now + 10.hours).iso8601, count_only: true), headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body.keys).to eq(['meta'])
    expect(meta).to include('due_today_count' => 1, 'open_count' => 2)

    get tasks_url(today_ends_at: 'yesterday-ish', count_only: true), headers: agent.create_new_auth_token, as: :json
    expect(meta['due_today_count']).to be_nil
  end

  it 'lists what was done in the last week, most recent first' do
    recent = task(completed_at: now - 1.hour)
    older = task(completed_at: now - 3.days)
    task(completed_at: now - 9.days)
    task

    get tasks_url(status: 'done'), headers: agent.create_new_auth_token, as: :json

    expect(payload.pluck('id')).to eq([recent.id, older.id])
  end

  it 'gives an administrator everyone’s tasks, and refuses that to an agent' do
    task
    task(user: admin)

    get tasks_url(scope: 'all'), headers: admin.create_new_auth_token, as: :json
    expect(payload.size).to eq(2)

    get tasks_url(scope: 'all'), headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'leaves out the tasks of a board the agent can no longer see' do
    task
    Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))

    get tasks_url, headers: agent.create_new_auth_token, as: :json

    expect(payload).to be_empty
    expect(meta['open_count']).to eq(0)
  end

  it 'filters by board' do
    other_card = create(:flow_kanban_card, stage: create(:flow_kanban_stage, board: create(:flow_kanban_board, account: account)))
    mine = task
    Custom::Kanban::CardTask.create!(card: other_card, user: agent, title: 'Outro', task_type: 'call', due_at: now + 1.day)

    get tasks_url(board_id: board.id), headers: agent.create_new_auth_token, as: :json

    expect(payload.pluck('id')).to eq([mine.id])
  end

  it 'pages through a long list' do
    stub_const('Api::V1::Accounts::Kanban::MyTasksController::PER_PAGE', 2)
    3.times { |index| task(due_at: now + (index + 1).hours) }

    get tasks_url(page: 1), headers: agent.create_new_auth_token, as: :json
    expect(payload.size).to eq(2)
    expect(meta['has_more']).to be(true)

    get tasks_url(page: 2), headers: agent.create_new_auth_token, as: :json
    expect(payload.size).to eq(1)
    expect(meta['has_more']).to be(false)
  end

  it 'does not reach another account' do
    other = create(:account)

    get "/api/v1/accounts/#{other.id}/kanban/my_tasks", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
