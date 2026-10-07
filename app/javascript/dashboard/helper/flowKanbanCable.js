import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';

// Spread into ActionCableConnector#events. The store is resolved per event, once Pinia is up.
const handle = action => data => useFlowKanbanStore()[action](data);

// A task about to fall due, sent to its assignee alone. The server writes the text in the
// account's language, so this works from any screen without loading the Kanban strings.
export const showTaskReminder = ({
  account_id: accountId,
  message,
  open_label: label,
}) =>
  useAlert(message, {
    type: 'link',
    to: frontendURL(`accounts/${accountId}/kanban`),
    message: label,
  });

export const flowKanbanCableEvents = {
  'kanban.board.updated': handle('onBoardUpdated'),
  'kanban.board.deleted': handle('onBoardDeleted'),
  'kanban.card.created': handle('onCardCreated'),
  'kanban.card.updated': handle('onCardUpdated'),
  'kanban.card.deleted': handle('onCardDeleted'),
  'kanban.task.reminder': showTaskReminder,
};
