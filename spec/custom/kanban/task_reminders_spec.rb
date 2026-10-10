require 'rails_helper'

RSpec.describe 'Kanban task reminders', type: :job do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:flow_kanban_board, account: account) }
  let(:stage) { create(:flow_kanban_stage, board: board) }
  let(:card) { create(:flow_kanban_card, stage: stage, title: 'Obra da Maria') }
  let(:now) { Time.zone.parse('2026-10-07 14:00:00') }

  def create_task(**attributes)
    Custom::Kanban::CardTask.create!({ card: card, user: agent, title: 'Ligar', task_type: 'call', due_at: now + 10.minutes }.merge(attributes))
  end

  around { |example| travel_to(now) { example.run } }

  describe Custom::Kanban::CardTask, '.due_for_reminder' do
    it 'takes open tasks from an hour overdue to 15 minutes ahead, not announced yet' do
      due_soon = create_task(due_at: now + 14.minutes)
      just_overdue = create_task(due_at: now - 50.minutes)
      create_task(due_at: now + 16.minutes)
      create_task(due_at: now - 70.minutes)
      create_task(completed_at: now - 1.minute)
      create_task(reminded_at: now - 1.minute)

      expect(described_class.due_for_reminder(now)).to contain_exactly(due_soon, just_overdue)
    end

    it 'announces a task again after its date changes or it is taken up again, but not after it is completed' do
      task = create_task(reminded_at: now - 1.minute)

      task.update!(completed: true)
      expect(task.reminded_at).to be_present

      task.update!(completed: false)
      expect(task.reminded_at).to be_nil

      task.update_columns(reminded_at: now) # rubocop:disable Rails/SkipsModelValidations
      task.update!(due_at: now + 1.hour)
      expect(task.reminded_at).to be_nil
    end
  end

  describe Custom::Kanban::TaskReminderJob do
    it 'tells the assigned agent alone, once, with the minutes left' do
      task = create_task(due_at: now + 10.minutes)

      expect { described_class.perform_now }.to have_enqueued_job(ActionCableBroadcastJob).with(
        [agent.pubsub_token], 'kanban.task.reminder',
        hash_including(account_id: account.id, task: { id: task.id, card_id: card.id, board_id: board.id },
                       message: a_string_including('10 min', 'Ligar', 'Obra da Maria'))
      )
      expect(task.reload.reminded_at).to eq(now)

      expect { described_class.perform_now }.not_to have_enqueued_job(ActionCableBroadcastJob)
    end

    it 'says overdue for a task already past its time' do
      create_task(due_at: now - 5.minutes)

      expect { described_class.perform_now }.to have_enqueued_job(ActionCableBroadcastJob).with(
        anything, 'kanban.task.reminder', hash_including(message: a_string_including('overdue', 'Ligar'))
      )
    end

    it 'writes the text in the account language' do
      account.update!(locale: 'pt_BR')
      create_task

      expect { described_class.perform_now }.to have_enqueued_job(ActionCableBroadcastJob).with(
        anything, 'kanban.task.reminder', hash_including(message: a_string_including('Tarefa vence em 10 min'), open_label: 'Abrir o funil')
      )
    end

    it 'does not name a card the agent can no longer see, and does not try again' do
      Custom::Kanban::BoardInbox.create!(board: board, inbox: create(:inbox, account: account))
      task = create_task

      expect { described_class.perform_now }.not_to have_enqueued_job(ActionCableBroadcastJob)
      expect(task.reload.reminded_at).to be_present
    end

    it 'leaves a task far from its date alone' do
      task = create_task(due_at: now + 2.hours)

      expect { described_class.perform_now }.not_to have_enqueued_job(ActionCableBroadcastJob)
      expect(task.reload.reminded_at).to be_nil
    end
  end
end
