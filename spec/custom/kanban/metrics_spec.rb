require 'rails_helper'

RSpec.describe Custom::Kanban::Metrics do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let(:stage) { create(:flow_kanban_stage, board: board, stale_after_days: 3) }
  let(:now) { Time.zone.parse('2026-10-08 10:00:00') }

  around { |example| travel_to(now) { example.run } }

  def card(**attributes)
    create(:flow_kanban_card, { stage: stage }.merge(attributes))
  end

  def task(**attributes)
    Custom::Kanban::CardTask.create!({ card: card, user: agent, title: 'Ligar', task_type: 'call', due_at: now + 1.day }.merge(attributes))
  end

  it 'counts deals by where they came from, the automatic ones still to review and the stalled' do
    card
    card(source: 'automatic', needs_review: true)
    card(source: 'automatic', needs_review: false)
    card.update_columns(stage_changed_at: now - 5.days) # rubocop:disable Rails/SkipsModelValidations
    create(:flow_kanban_card) # another account

    deals = described_class.new(account, since: 1.day.ago).to_h[:deals]

    expect(deals).to eq(created_manually: 2, created_automatically: 2, automatic_share: 0.5,
                        automatic_awaiting_review: 1, stalled_now: 1)
  end

  it 'counts the tasks done late against all done, and the overdue ones' do
    task(due_at: now - 2.days, completed_at: now - 1.day)
    task(due_at: now + 2.days, completed_at: now - 1.hour)
    task(due_at: now - 1.hour)

    tasks = described_class.new(account, since: 3.days.ago).to_h[:tasks]

    expect(tasks).to eq(created: 3, completed: 2, completed_late: 1, completed_late_share: 0.5, overdue_now: 1)
  end

  it 'counts notifications sent and opened, by kind, and leaves a rate empty rather than dividing by zero' do
    deal = card
    Custom::Kanban::Notification.create!(account: account, user: agent, card: deal, kind: 'task_due', read_at: now)
    Custom::Kanban::Notification.create!(account: account, user: agent, card: deal, kind: 'card_stale')
    Custom::Kanban::Notification.where(kind: 'card_assigned').delete_all

    metrics = described_class.new(account, since: 1.day.ago).to_h

    expect(metrics[:notifications]).to eq(sent: 2, opened: 1, opened_share: 0.5, by_kind: { 'task_due' => 1, 'card_stale' => 1 })
    expect(described_class.new(create(:account)).to_h[:tasks][:completed_late_share]).to be_nil
  end

  it 'holds counts and rates only' do
    card(title: 'Obra da Maria')

    expect(described_class.new(account).to_h.to_json).not_to include('Obra da Maria')
  end
end
