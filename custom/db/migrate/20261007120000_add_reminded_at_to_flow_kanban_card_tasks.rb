# Kanban phase 3: when the reminder of a task went out, so a task is announced once however many
# workers run the reminder job. A task whose date or status changes is announced again.
class AddRemindedAtToFlowKanbanCardTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :flow_kanban_card_tasks, :reminded_at, :datetime

    # The job's query: open tasks not yet announced, by due date.
    add_index :flow_kanban_card_tasks, :due_at, where: 'completed_at IS NULL AND reminded_at IS NULL',
                                                name: 'index_flow_kanban_tasks_awaiting_reminder'
  end
end
