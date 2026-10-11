import { flowKanbanCableEvents, showTaskReminder } from '../flowKanbanCable';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/stores/flowKanban', () => ({ useFlowKanbanStore: vi.fn() }));

describe('flowKanbanCable', () => {
  it('shows a task reminder as a toast that links to the board', () => {
    showTaskReminder({
      account_id: 7,
      message: 'Tarefa vence em 10 min: Ligar (Obra da Maria)',
      open_label: 'Abrir o funil',
    });

    expect(useAlert).toHaveBeenCalledWith(
      'Tarefa vence em 10 min: Ligar (Obra da Maria)',
      {
        type: 'link',
        to: expect.stringContaining('accounts/7/kanban'),
        message: 'Abrir o funil',
      }
    );
  });

  it('listens for the reminder next to the board and card events', () => {
    expect(Object.keys(flowKanbanCableEvents)).toEqual(
      expect.arrayContaining([
        'kanban.card.updated',
        'kanban.board.updated',
        'kanban.task.reminder',
      ])
    );
    expect(flowKanbanCableEvents['kanban.task.reminder']).toBe(
      showTaskReminder
    );
  });
});
