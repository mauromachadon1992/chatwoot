import { frontendURL } from '../../../helper/URLHelper';
// Flow: our Kanban replaces the fazer.ai Pro paywall at the same route.
import KanbanIndex from '../flowKanban/KanbanPage.vue';

const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/kanban'),
    component: KanbanIndex,
    name: 'kanban_view',
    meta,
  },
];
