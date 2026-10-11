import { createPinia, setActivePinia } from 'pinia';
import FlowKanbanAPI from 'dashboard/api/flowKanban';
import { useFlowKanbanStore } from '../flowKanban';

vi.mock('dashboard/api/flowKanban', () => ({
  default: {
    getNotifications: vi.fn(),
    readNotification: vi.fn(),
    readAllNotifications: vi.fn(),
  },
}));

const item = (id, readAt = null) => ({ id, read_at: readAt, kind: 'task_due' });

describe('flowKanban store: notifications', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useFlowKanbanStore();
    vi.clearAllMocks();
  });

  it('loads the list and the unread count the server computed', async () => {
    FlowKanbanAPI.getNotifications.mockResolvedValue({
      data: { payload: [item(2), item(1, 5)], meta: { unread_count: 7 } },
    });

    await store.fetchNotifications();

    expect(store.notifications.map(n => n.id)).toEqual([2, 1]);
    expect(store.unreadCount).toBe(7);
    expect(store.notificationsLoaded).toBe(true);
  });

  it('puts a notification that arrives in realtime on top, once, with the server count', () => {
    store.notifications = [item(1)];

    store.onNotificationCreated({ notification: item(2), unread_count: 2 });
    store.onNotificationCreated({ notification: item(2), unread_count: 2 });

    expect(store.notifications.map(n => n.id)).toEqual([2, 1]);
    expect(store.unreadCount).toBe(2);
  });

  it('marks one read from the server answer, and does not ask again for one already read', async () => {
    store.notifications = [item(1), item(2)];
    store.unreadCount = 2;
    FlowKanbanAPI.readNotification.mockResolvedValue({
      data: { payload: item(1, 9), meta: { unread_count: 1 } },
    });

    await store.markNotificationRead(store.notifications[0]);
    await store.markNotificationRead(store.notifications[0]);

    expect(FlowKanbanAPI.readNotification).toHaveBeenCalledTimes(1);
    expect(store.notifications[0].read_at).toBe(9);
    expect(store.unreadCount).toBe(1);
  });

  it('marks all read', async () => {
    store.notifications = [item(1), item(2, 3)];
    store.unreadCount = 1;
    FlowKanbanAPI.readAllNotifications.mockResolvedValue({
      data: { meta: { unread_count: 0 } },
    });

    await store.markAllNotificationsRead();

    expect(store.notifications.every(n => n.read_at)).toBe(true);
    expect(store.notifications[1].read_at).toBe(3);
    expect(store.unreadCount).toBe(0);
  });
});
