/* global axios */
import ApiClient from './ApiClient';

class FlowKanbanAPI extends ApiClient {
  constructor() {
    super('kanban', { accountScoped: true });
  }

  getBoards() {
    return axios.get(`${this.url}/boards`);
  }

  createBoard(data) {
    return axios.post(`${this.url}/boards`, data);
  }

  updateBoard(boardId, data) {
    return axios.patch(`${this.url}/boards/${boardId}`, data);
  }

  deleteBoard(boardId) {
    return axios.delete(`${this.url}/boards/${boardId}`);
  }

  createStage(boardId, data) {
    return axios.post(`${this.url}/boards/${boardId}/stages`, data);
  }

  updateStage(boardId, stageId, data) {
    return axios.patch(`${this.url}/boards/${boardId}/stages/${stageId}`, data);
  }

  deleteStage(boardId, stageId, moveToStageId) {
    return axios.delete(`${this.url}/boards/${boardId}/stages/${stageId}`, {
      params: { move_to_stage_id: moveToStageId },
    });
  }

  reorderStages(boardId, stageIds) {
    return axios.patch(`${this.url}/boards/${boardId}/stages/reorder`, {
      stage_ids: stageIds,
    });
  }

  getCards(boardId, { stageId, offset, filters = {} } = {}) {
    return axios.get(`${this.url}/boards/${boardId}/cards`, {
      params: { stage_id: stageId, offset, ...filters },
    });
  }

  getCard(cardId) {
    return axios.get(`${this.url}/cards/${cardId}`);
  }

  createCard(data) {
    return axios.post(`${this.url}/cards`, data);
  }

  updateCard(cardId, data) {
    return axios.patch(`${this.url}/cards/${cardId}`, data);
  }

  // Onto a lost stage, `lostReasonId` and `lostNote` say why (both optional).
  moveCard(
    cardId,
    { stageId, previousCardId, nextCardId, lostReasonId, lostNote }
  ) {
    return axios.patch(`${this.url}/cards/${cardId}/move`, {
      stage_id: stageId,
      previous_card_id: previousCardId,
      next_card_id: nextCardId,
      lost_reason_id: lostReasonId,
      lost_note: lostNote,
    });
  }

  getCardEvents(cardId, { page } = {}) {
    return axios.get(`${this.url}/cards/${cardId}/events`, {
      params: { page },
    });
  }

  // The quote message and totals as the server builds them (the agent's tool reads the same text).
  getQuotePreview(cardId, locale) {
    return axios.get(`${this.url}/cards/${cardId}/quote_preview`, {
      params: { locale },
    });
  }

  // Writes the quote taken to a conversation in the deal's history.
  recordQuote(cardId, conversationDisplayId) {
    return axios.post(`${this.url}/cards/${cardId}/quote`, {
      conversation_id: conversationDisplayId,
    });
  }

  getLostReasons() {
    return axios.get(`${this.url}/lost_reasons`);
  }

  createLostReason(name) {
    return axios.post(`${this.url}/lost_reasons`, { name });
  }

  updateLostReason(reasonId, name) {
    return axios.patch(`${this.url}/lost_reasons/${reasonId}`, { name });
  }

  deleteLostReason(reasonId) {
    return axios.delete(`${this.url}/lost_reasons/${reasonId}`);
  }

  createAiSummary(cardId) {
    return axios.post(`${this.url}/cards/${cardId}/ai_summary`);
  }

  decideAiDraft(draftId, decision) {
    return axios.post(`${this.url}/ai_drafts/${draftId}/decide`, { decision });
  }

  exportProducts() {
    return axios.get(`${this.url}/products/export`, { responseType: 'blob' });
  }

  exportDeals(boardId, filters = {}) {
    return axios.get(`${this.url}/boards/${boardId}/cards/export`, {
      params: filters,
      responseType: 'blob',
    });
  }

  createImport({ file, kind, boardId }) {
    const body = new FormData();
    body.append('file', file);
    body.append('kind', kind);
    if (boardId) body.append('board_id', boardId);
    return axios.post(`${this.url}/imports`, body);
  }

  updateImport(importId, mapping) {
    return axios.patch(`${this.url}/imports/${importId}`, { mapping });
  }

  runImport(importId) {
    return axios.post(`${this.url}/imports/${importId}/run`);
  }

  getImport(importId) {
    return axios.get(`${this.url}/imports/${importId}`);
  }

  downloadImportErrors(importId) {
    return axios.get(`${this.url}/imports/${importId}/errors`, {
      responseType: 'blob',
    });
  }

  getWebhooks() {
    return axios.get(`${this.url}/webhooks`);
  }

  createWebhook(data) {
    return axios.post(`${this.url}/webhooks`, data);
  }

  updateWebhook(webhookId, data) {
    return axios.patch(`${this.url}/webhooks/${webhookId}`, data);
  }

  deleteWebhook(webhookId) {
    return axios.delete(`${this.url}/webhooks/${webhookId}`);
  }

  getWebhookDeliveries(webhookId) {
    return axios.get(`${this.url}/webhooks/${webhookId}/deliveries`);
  }

  testWebhook(webhookId) {
    return axios.post(`${this.url}/webhooks/${webhookId}/test`);
  }

  deleteCard(cardId) {
    return axios.delete(`${this.url}/cards/${cardId}`);
  }

  linkConversation(cardId, conversationDisplayId) {
    return axios.post(`${this.url}/cards/${cardId}/conversations`, {
      conversation_id: conversationDisplayId,
    });
  }

  unlinkConversation(cardId, conversationDisplayId) {
    return axios.delete(
      `${this.url}/cards/${cardId}/conversations/${conversationDisplayId}`
    );
  }

  getConversationCards(conversationDisplayId) {
    return axios.get(
      `${this.url}/conversations/${conversationDisplayId}/cards`
    );
  }

  addCardItem(cardId, data) {
    return axios.post(`${this.url}/cards/${cardId}/items`, data);
  }

  updateCardItem(cardId, itemId, data) {
    return axios.patch(`${this.url}/cards/${cardId}/items/${itemId}`, data);
  }

  removeCardItem(cardId, itemId) {
    return axios.delete(`${this.url}/cards/${cardId}/items/${itemId}`);
  }

  // My tasks. `todayEndsAt` is the end of the viewer's day, so the server can count "today".
  getTasks({ scope, status, page, boardId, todayEndsAt, countOnly } = {}) {
    return axios.get(`${this.url}/my_tasks`, {
      params: {
        scope,
        status,
        page,
        board_id: boardId,
        today_ends_at: todayEndsAt,
        count_only: countOnly,
      },
    });
  }

  getNotifications({ page } = {}) {
    return axios.get(`${this.url}/notifications`, { params: { page } });
  }

  readNotification(notificationId) {
    return axios.patch(`${this.url}/notifications/${notificationId}`);
  }

  readAllNotifications() {
    return axios.post(`${this.url}/notifications/read_all`);
  }

  getCardTasks(cardId) {
    return axios.get(`${this.url}/cards/${cardId}/tasks`);
  }

  createCardTask(cardId, data) {
    return axios.post(`${this.url}/cards/${cardId}/tasks`, data);
  }

  updateCardTask(cardId, taskId, data) {
    return axios.patch(`${this.url}/cards/${cardId}/tasks/${taskId}`, data);
  }

  removeCardTask(cardId, taskId) {
    return axios.delete(`${this.url}/cards/${cardId}/tasks/${taskId}`);
  }

  getAutomations(boardId) {
    return axios.get(`${this.url}/boards/${boardId}/automations`);
  }

  getAutomationRuns(boardId) {
    return axios.get(`${this.url}/boards/${boardId}/automations/runs`);
  }

  createAutomation(boardId, data) {
    return axios.post(`${this.url}/boards/${boardId}/automations`, data);
  }

  updateAutomation(boardId, automationId, data) {
    return axios.patch(
      `${this.url}/boards/${boardId}/automations/${automationId}`,
      data
    );
  }

  removeAutomation(boardId, automationId) {
    return axios.delete(
      `${this.url}/boards/${boardId}/automations/${automationId}`
    );
  }

  getProducts({ q, page, active } = {}) {
    return axios.get(`${this.url}/products`, { params: { q, page, active } });
  }

  createProduct(data) {
    return axios.post(`${this.url}/products`, data);
  }

  updateProduct(productId, data) {
    return axios.patch(`${this.url}/products/${productId}`, data);
  }

  deleteProduct(productId) {
    return axios.delete(`${this.url}/products/${productId}`);
  }

  getSettings() {
    return axios.get(`${this.url}/settings`);
  }

  updateSettings(data) {
    return axios.patch(`${this.url}/settings`, data);
  }

  getReport(boardId, { since, until, assigneeId } = {}) {
    return axios.get(`${this.url}/boards/${boardId}/report`, {
      params: { since, until, assignee_id: assigneeId },
    });
  }
}

export default new FlowKanbanAPI();
