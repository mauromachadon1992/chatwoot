import { setActivePinia, createPinia } from 'pinia';
import FlowKanbanAPI from 'dashboard/api/flowKanban';
import { useFlowKanbanStore } from '../flowKanban';

vi.mock('dashboard/api/flowKanban', () => ({
  default: {
    getBoards: vi.fn(),
    getCards: vi.fn(),
    moveCard: vi.fn(),
  },
}));

const card = (id, stageId, position, extra = {}) => ({
  id,
  board_id: 1,
  stage_id: stageId,
  position,
  conversations: [],
  ...extra,
});

const setupBoard = store => {
  store.boards = [
    {
      id: 1,
      name: 'Vendas',
      stages: [
        { id: 10, name: 'Novo' },
        { id: 20, name: 'Ganho' },
      ],
    },
  ];
  store.activeBoardId = 1;
  store.columns = {
    10: { cards: [card(1, 10, 0), card(2, 10, 1024)], total: 2 },
    20: { cards: [card(3, 20, 0)], total: 1 },
  };
};

describe('useFlowKanbanStore', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useFlowKanbanStore();
    setupBoard(store);
    vi.clearAllMocks();
  });

  describe('upsertCard', () => {
    it('moves a card to its new stage by position and fixes both totals', () => {
      store.upsertCard(card(1, 20, 512));

      expect(store.columns[10].cards.map(c => c.id)).toEqual([2]);
      expect(store.columns[10].total).toBe(1);
      expect(store.columns[20].cards.map(c => c.id)).toEqual([3, 1]);
      expect(store.columns[20].total).toBe(2);
    });

    it('inserts a card created elsewhere in position', () => {
      store.upsertCard(card(4, 10, 512));

      expect(store.columns[10].cards.map(c => c.id)).toEqual([1, 4, 2]);
      expect(store.columns[10].total).toBe(3);
    });

    it('ignores unknown cards while filters are on, since they may not match', () => {
      store.filters.q = 'acme';
      store.upsertCard(card(4, 10, 512));

      expect(store.columns[10].cards.map(c => c.id)).toEqual([1, 2]);
      expect(store.columns[10].total).toBe(2);
    });

    it('does not place a card past the loaded end of a column with more to load', () => {
      store.columns[10].total = 30;
      store.upsertCard(card(4, 10, 9000));

      expect(store.columns[10].cards.map(c => c.id)).toEqual([1, 2]);
      expect(store.columns[10].total).toBe(31);
    });

    it('leaves cards of other boards alone but still signals the event', () => {
      store.upsertCard(card(4, 99, 0, { board_id: 2 }));

      expect(store.columns[10].cards).toHaveLength(2);
      expect(store.lastCardEvent.card.id).toBe(4);
    });
  });

  describe('moveCard', () => {
    it('sends the neighbours around the drop point and applies the server position', async () => {
      // vuedraggable has already moved card 1 into stage 20, below card 3.
      const moved = store.columns[10].cards.shift();
      store.columns[20].cards.push(moved);
      FlowKanbanAPI.moveCard.mockResolvedValue({
        data: { payload: card(1, 20, 1024) },
      });

      await store.moveCard({
        card: moved,
        fromStageId: 10,
        toStageId: 20,
        newIndex: 1,
      });

      expect(FlowKanbanAPI.moveCard).toHaveBeenCalledWith(1, {
        stageId: 20,
        previousCardId: 3,
        nextCardId: undefined,
      });
      expect(store.columns[10].total).toBe(1);
      expect(store.columns[20].total).toBe(2);
      expect(store.columns[20].cards.map(c => c.id)).toEqual([3, 1]);
    });

    it('reloads the board when the server refuses the move', async () => {
      FlowKanbanAPI.moveCard.mockRejectedValue(new Error('nope'));
      FlowKanbanAPI.getCards.mockResolvedValue({ data: { payload: [] } });

      await expect(
        store.moveCard({
          card: store.columns[10].cards[0],
          fromStageId: 10,
          toStageId: 10,
          newIndex: 0,
        })
      ).rejects.toThrow('nope');
      expect(FlowKanbanAPI.getCards).toHaveBeenCalled();
    });
  });

  describe('onBoardUpdated', () => {
    it('falls back to another board when the agent lost access to the active one', async () => {
      FlowKanbanAPI.getBoards.mockResolvedValue({
        data: { payload: [{ id: 2, name: 'Pós-venda', stages: [] }] },
      });
      FlowKanbanAPI.getCards.mockResolvedValue({ data: { payload: [] } });

      await store.onBoardUpdated({ board: { id: 1 } });

      expect(store.activeBoardId).toBe(2);
      expect(FlowKanbanAPI.getCards).toHaveBeenCalledWith(2, { filters: {} });
    });
  });
});
