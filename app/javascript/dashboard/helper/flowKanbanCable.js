import { useFlowKanbanStore } from 'dashboard/stores/flowKanban';

// Spread into ActionCableConnector#events. The store is resolved per event, once Pinia is up.
const handle = action => data => useFlowKanbanStore()[action](data);

export const flowKanbanCableEvents = {
  'kanban.board.updated': handle('onBoardUpdated'),
  'kanban.board.deleted': handle('onBoardDeleted'),
  'kanban.card.created': handle('onCardCreated'),
  'kanban.card.updated': handle('onCardUpdated'),
  'kanban.card.deleted': handle('onCardDeleted'),
};
