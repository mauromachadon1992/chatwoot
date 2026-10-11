import { defineStore } from 'pinia';
import FlowKanbanAPI from 'dashboard/api/flowKanban';

const LAST_BOARD_KEY = 'flow_kanban_last_board';

const readLastBoard = () => {
  try {
    return Number(window.localStorage.getItem(LAST_BOARD_KEY)) || null;
  } catch {
    return null;
  }
};

const writeLastBoard = boardId => {
  try {
    window.localStorage.setItem(LAST_BOARD_KEY, String(boardId));
  } catch {
    // Storage blocked: the board simply is not remembered.
  }
};

const byPosition = (a, b) => a.position - b.position || a.id - b.id;

// `status`: the Situation filter, 'stale' or 'overdue_tasks'.
const emptyFilters = () => ({
  q: '',
  assignee_id: '',
  inbox_id: '',
  status: '',
});

export const useFlowKanbanStore = defineStore('flowKanban', {
  state: () => ({
    boards: [],
    boardsLoaded: false,
    activeBoardId: null,
    // stageId -> { cards, total, totalValue, isLoading }. `total` and `totalValue` describe
    // the whole filtered stage, not only the cards loaded so far.
    columns: {},
    isLoadingCards: false,
    filters: emptyFilters(),
    // Bumped on every card event, so panels outside the board can refresh.
    lastCardEvent: null,
    // The bell: the agent's own notifications, newest first, and how many are unread (the
    // server counts them, so the badge is right even when the list holds only the first page).
    notifications: [],
    unreadCount: 0,
    notificationsLoaded: false,
    // The badge of My tasks: the agent's own tasks overdue and due today.
    taskCounts: { overdue: 0, dueToday: 0 },
  }),

  getters: {
    activeBoard: state =>
      state.boards.find(board => board.id === state.activeBoardId) || null,
    stages() {
      return this.activeBoard?.stages || [];
    },
    hasActiveFilters: state =>
      Object.values(state.filters).some(value => value !== ''),
    activeFilterParams: state =>
      Object.fromEntries(
        Object.entries(state.filters).filter(([, value]) => value !== '')
      ),
  },

  actions: {
    async fetchBoards() {
      const { data } = await FlowKanbanAPI.getBoards();
      this.boards = data.payload;
      this.boardsLoaded = true;
      const remembered = readLastBoard();
      const fallback = this.boards[0]?.id || null;
      const stillVisible = id => this.boards.some(board => board.id === id);
      if (!stillVisible(this.activeBoardId)) {
        this.activeBoardId = stillVisible(remembered) ? remembered : fallback;
      }
    },

    async selectBoard(boardId) {
      this.activeBoardId = boardId;
      writeLastBoard(boardId);
      await this.fetchCards();
    },

    async fetchCards() {
      if (!this.activeBoardId) {
        this.columns = {};
        return;
      }
      const boardId = this.activeBoardId;
      this.isLoadingCards = true;
      try {
        const { data } = await FlowKanbanAPI.getCards(boardId, {
          filters: this.activeFilterParams,
        });
        if (boardId !== this.activeBoardId) return;
        this.columns = Object.fromEntries(
          data.payload.map(column => [
            column.stage_id,
            {
              cards: column.cards,
              total: column.total,
              totalValue: column.total_value_cents || 0,
              isLoading: false,
            },
          ])
        );
      } finally {
        this.isLoadingCards = false;
      }
    },

    async loadMore(stageId) {
      const column = this.columns[stageId];
      if (!column || column.isLoading || column.cards.length >= column.total)
        return;
      column.isLoading = true;
      try {
        const { data } = await FlowKanbanAPI.getCards(this.activeBoardId, {
          stageId,
          offset: column.cards.length,
          filters: this.activeFilterParams,
        });
        const [page] = data.payload;
        const known = new Set(column.cards.map(card => card.id));
        column.cards.push(...page.cards.filter(card => !known.has(card.id)));
        column.total = page.total;
        column.totalValue = page.total_value_cents || 0;
      } finally {
        column.isLoading = false;
      }
    },

    setFilters(filters) {
      this.filters = { ...this.filters, ...filters };
      return this.fetchCards();
    },

    resetFilters() {
      this.filters = emptyFilters();
      return this.fetchCards();
    },

    async createBoard(payload) {
      const { data } = await FlowKanbanAPI.createBoard(payload);
      this.upsertBoard(data.payload);
      await this.selectBoard(data.payload.id);
      return data.payload;
    },

    async updateBoard(boardId, payload) {
      const { data } = await FlowKanbanAPI.updateBoard(boardId, payload);
      this.upsertBoard(data.payload);
      return data.payload;
    },

    async deleteBoard(boardId) {
      await FlowKanbanAPI.deleteBoard(boardId);
      this.removeBoard(boardId);
    },

    async createStage(payload) {
      await FlowKanbanAPI.createStage(this.activeBoardId, payload);
      await this.refreshActiveBoard();
    },

    async updateStage(stageId, payload) {
      await FlowKanbanAPI.updateStage(this.activeBoardId, stageId, payload);
      await this.refreshActiveBoard();
    },

    async deleteStage(stageId, moveToStageId) {
      await FlowKanbanAPI.deleteStage(
        this.activeBoardId,
        stageId,
        moveToStageId
      );
      await this.refreshActiveBoard();
      await this.fetchCards();
    },

    async reorderStages(stageIds) {
      const { data } = await FlowKanbanAPI.reorderStages(
        this.activeBoardId,
        stageIds
      );
      this.upsertBoard(data.payload);
    },

    async refreshActiveBoard() {
      await this.fetchBoards();
      this.ensureColumns();
    },

    async createCard(payload) {
      const { data } = await FlowKanbanAPI.createCard(payload);
      this.upsertCard(data.payload, { created: true });
      return data.payload;
    },

    async updateCard(cardId, payload) {
      const { data } = await FlowKanbanAPI.updateCard(cardId, payload);
      this.upsertCard(data.payload);
      return data.payload;
    },

    async deleteCard(card) {
      await FlowKanbanAPI.deleteCard(card.id);
      this.removeCard(card);
    },

    async linkConversation(cardId, conversationDisplayId) {
      const { data } = await FlowKanbanAPI.linkConversation(
        cardId,
        conversationDisplayId
      );
      this.upsertCard(data.payload);
      return data.payload;
    },

    async unlinkConversation(cardId, conversationDisplayId) {
      const { data } = await FlowKanbanAPI.unlinkConversation(
        cardId,
        conversationDisplayId
      );
      this.upsertCard(data.payload);
      return data.payload;
    },

    // vuedraggable has already put the card in its new slot; this records the move and
    // asks the server for the position between the neighbours the agent saw.
    async moveCard({
      card,
      fromStageId,
      toStageId,
      newIndex,
      lostReasonId,
      lostNote,
    }) {
      const column = this.columns[toStageId];
      if (fromStageId !== toStageId) {
        this.columns[fromStageId].total -= 1;
        this.columns[fromStageId].totalValue -= card.value_cents || 0;
        column.total += 1;
        column.totalValue += card.value_cents || 0;
      }
      card.stage_id = toStageId;
      const previousCard = column.cards[newIndex - 1];
      const nextCard = column.cards[newIndex + 1];
      try {
        const { data } = await FlowKanbanAPI.moveCard(card.id, {
          stageId: toStageId,
          previousCardId: previousCard?.id,
          nextCardId: nextCard?.id,
          lostReasonId,
          lostNote,
        });
        this.upsertCard(data.payload);
      } catch (error) {
        await this.fetchCards();
        throw error;
      }
    },

    ensureColumns() {
      this.stages.forEach(stage => {
        if (!this.columns[stage.id]) {
          this.columns[stage.id] = {
            cards: [],
            total: 0,
            totalValue: 0,
            isLoading: false,
          };
        }
      });
    },

    findCard(cardId) {
      const entry = Object.entries(this.columns).find(([, column]) =>
        column.cards.some(card => card.id === cardId)
      );
      if (!entry) return null;
      return { stageId: Number(entry[0]), column: entry[1] };
    },

    upsertBoard(board) {
      const index = this.boards.findIndex(item => item.id === board.id);
      if (index === -1) this.boards.push(board);
      else this.boards.splice(index, 1, board);
      if (board.id === this.activeBoardId) this.ensureColumns();
    },

    removeBoard(boardId) {
      this.boards = this.boards.filter(board => board.id !== boardId);
      if (this.activeBoardId === boardId) {
        this.activeBoardId = this.boards[0]?.id || null;
        this.fetchCards();
      }
    },

    // Places the card where its stage and position say. A card the board has never shown is
    // only inserted when no filter is active, since the dashboard cannot tell whether it
    // matches; and never past the last loaded card of a column that has more to load.
    upsertCard(card, { created = false } = {}) {
      this.lastCardEvent = { card, at: Date.now() };
      if (card.board_id !== this.activeBoardId) return;

      const location = this.findCard(card.id);
      if (location) {
        const previous = location.column.cards.find(
          item => item.id === card.id
        );
        location.column.cards = location.column.cards.filter(
          item => item.id !== card.id
        );
        location.column.totalValue -= previous.value_cents || 0;
        if (location.stageId !== card.stage_id) location.column.total -= 1;
      } else if (this.hasActiveFilters && !created) {
        return;
      }

      const column = this.columns[card.stage_id];
      if (!column) return;
      if (!location || location.stageId !== card.stage_id) column.total += 1;
      column.totalValue += card.value_cents || 0;

      const index = column.cards.findIndex(item => byPosition(card, item) < 0);
      const hasMore = column.total > column.cards.length + 1;
      if (index === -1 && hasMore) return;
      if (index === -1) column.cards.push(card);
      else column.cards.splice(index, 0, card);
    },

    removeCard(card) {
      this.lastCardEvent = { card, deleted: true, at: Date.now() };
      const location = this.findCard(card.id);
      if (!location) return;
      const previous = location.column.cards.find(item => item.id === card.id);
      location.column.cards = location.column.cards.filter(
        item => item.id !== card.id
      );
      location.column.total -= 1;
      location.column.totalValue -= previous.value_cents || 0;
    },

    // ActionCable handlers (see helper/flowKanbanCable.js).
    // Refetches the list rather than trusting the payload: a restriction change may have
    // taken the board away from this agent, and only the server knows.
    async onBoardUpdated({ board }) {
      const stageIds = b => (b?.stages || []).map(stage => stage.id).join();
      const previous = this.boards.find(item => item.id === board.id);
      const wasActive = this.activeBoardId === board.id;
      await this.fetchBoards();
      const current = this.boards.find(item => item.id === board.id);
      if (!current) {
        // fetchBoards already fell back to another board; show its cards.
        if (wasActive) this.fetchCards();
        return;
      }
      this.ensureColumns();
      if (
        board.id === this.activeBoardId &&
        stageIds(previous) !== stageIds(current)
      ) {
        this.fetchCards();
      }
    },

    onBoardDeleted({ board }) {
      this.removeBoard(board.id);
    },

    onCardCreated({ card }) {
      this.upsertCard(card);
    },

    onCardUpdated({ card }) {
      this.upsertCard(card);
    },

    onCardDeleted({ card }) {
      this.removeCard(card);
    },

    async fetchTaskCounts(todayEndsAt) {
      const { data } = await FlowKanbanAPI.getTasks({
        todayEndsAt,
        countOnly: true,
      });
      this.taskCounts = {
        overdue: data.meta.overdue_count,
        dueToday: data.meta.due_today_count || 0,
      };
    },

    async fetchNotifications() {
      const { data } = await FlowKanbanAPI.getNotifications();
      this.notifications = data.payload;
      this.unreadCount = data.meta.unread_count;
      this.notificationsLoaded = true;
    },

    async markNotificationRead(notification) {
      if (notification.read_at) return;
      const { data } = await FlowKanbanAPI.readNotification(notification.id);
      this.notifications = this.notifications.map(item =>
        item.id === notification.id ? data.payload : item
      );
      this.unreadCount = data.meta.unread_count;
    },

    async markAllNotificationsRead() {
      const { data } = await FlowKanbanAPI.readAllNotifications();
      const now = Math.floor(Date.now() / 1000);
      this.notifications = this.notifications.map(item => ({
        ...item,
        read_at: item.read_at || now,
      }));
      this.unreadCount = data.meta.unread_count;
    },

    onNotificationCreated({ notification, unread_count: unreadCount }) {
      if (!this.notifications.some(item => item.id === notification.id))
        this.notifications = [notification, ...this.notifications];
      this.unreadCount = unreadCount;
    },
  },
});
