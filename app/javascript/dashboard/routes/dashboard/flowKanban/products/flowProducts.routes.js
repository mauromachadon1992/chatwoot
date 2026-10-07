import { frontendURL } from 'dashboard/helper/URLHelper';
import SettingsWrapper from '../../settings/SettingsWrapper.vue';
import ProductsPage from './ProductsPage.vue';
import KanbanSettingsPage from '../KanbanSettingsPage.vue';

// Settings → Products (the Kanban product catalog and the deal currency) and Settings → Kanban
// (lost reasons and the quote message). Administrators only; the sidebar hides the entries from
// everyone else through these permissions.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/kanban'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'flow_kanban_settings',
          meta: { permissions: ['administrator'] },
          component: KanbanSettingsPage,
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/products'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'flow_products_list',
          meta: { permissions: ['administrator'] },
          component: ProductsPage,
        },
      ],
    },
  ],
};
