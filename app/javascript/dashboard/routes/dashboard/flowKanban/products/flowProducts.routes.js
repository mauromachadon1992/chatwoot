import { frontendURL } from 'dashboard/helper/URLHelper';
import SettingsWrapper from '../../settings/SettingsWrapper.vue';
import ProductsPage from './ProductsPage.vue';

// Settings → Products: the Kanban product catalog and the deal currency. Administrators
// only; the sidebar hides the entry from everyone else through these permissions.
export default {
  routes: [
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
