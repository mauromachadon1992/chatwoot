// Staging recipe (B-13): a small catalog, a vault entry for the agents' service token, three HTTP tools (read the deal of the
// conversation, search the catalog, add a product to the deal) and the grants on agent 2. Run once with Node 20+:
//   FLEET=<agents fleet key> ADMIN=<chatwoot admin token> SERVICE=<service user token> [VAULT_REF=vault:N] node custom/script/agents-http-tools.mjs
// Secrets come only from the environment; nothing is written to disk or printed. Gotcha: in the grants, `enabledTools: []` means NO
// native tool; list the natives by name, as step 4 does. Hosts, ids and prices below are the staging ones.
const { FLEET, ADMIN, SERVICE } = process.env;
const CHAT = 'https://chat-hml.freitascasaeconstrucao.com.br';
const AGENTS = 'https://agentes-hml.freitascasaeconstrucao.com.br/api/v1';
const HOST = 'chat-hml.freitascasaeconstrucao.com.br';

const call = async (url, options = {}) => {
  const response = await fetch(url, options);
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = text;
  }
  if (!response.ok) throw new Error(`${options.method || 'GET'} ${url} -> ${response.status} ${text.slice(0, 300)}`);
  return body;
};

const chatwoot = (path, method = 'GET', body) =>
  call(`${CHAT}/api/v1/accounts/1/${path}`, {
    method,
    headers: { 'api_access_token': ADMIN, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });

const agents = (path, method = 'GET', body) =>
  call(`${AGENTS}/${path}`, {
    method,
    headers: { Authorization: `Bearer ${FLEET}`, 'X-Tenant-Id': '1', 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });

(async () => {
  // 1. catalog
  const wanted = [
    { name: 'Concreto fck 25', sku: 'CON-25', unit: 'm3', price_cents: 48000 },
    { name: 'Concreto fck 30', sku: 'CON-30', unit: 'm3', price_cents: 52000 },
    { name: 'Bombeamento', sku: 'BOMBA', unit: 'm3', price_cents: 9000 },
  ];
  const have = (await chatwoot('kanban/products?q=')).payload.map(product => product.sku);
  for (const product of wanted.filter(item => !have.includes(item.sku))) {
    await chatwoot('kanban/products', 'POST', { ...product, active: true });
  }
  const catalog = (await chatwoot('kanban/products?active=true')).payload;
  console.log('catalog:', catalog.map(p => `${p.id}:${p.sku}:${p.price_cents}`).join(' '));

  // 2. vault entry: the header api_access_token carries the service token, injected, never shown to the model
  const credentialRef =
    process.env.VAULT_REF ||
    (
      await agents('vault', 'POST', {
        name: 'Chatwoot staging (usuario de servico)',
        kind: 'header',
        paramName: 'api_access_token',
        baseUrl: CHAT,
        value: SERVICE,
      })
    ).ref;
  console.log('vault:', credentialRef);

  // 3. tools
  const common = { allowedHosts: [HOST], credentialRef, enabled: true };
  const tools = [
    {
      ...common,
      name: 'search_products',
      label: 'Buscar produtos',
      description:
        'Busca produtos ativos no catalogo da empresa pelo nome ou SKU (ex.: "concreto", "bomba"). Devolve id, name, sku, unit e price_cents (preco em CENTAVOS: 48000 = R$ 480,00). Use SEMPRE o catalogo; nunca invente preco.',
      method: 'GET',
      urlTemplate: `${CHAT}/api/v1/accounts/1/kanban/products`,
      query: { q: '{{q}}', active: 'true' },
      inputSchema: { q: { type: 'string', required: true, description: 'Parte do nome ou SKU do produto.' } },
    },
    {
      ...common,
      name: 'get_current_deal',
      label: 'Ver negocio da conversa',
      description:
        'Mostra o negocio (card do Kanban) ligado a esta conversa: id do card, titulo, etapa e valor. Chame antes de adicionar produtos, para obter o card_id.',
      method: 'GET',
      urlTemplate: `${CHAT}/api/v1/accounts/1/conversations/{{conversation_id}}`,
      outputSchema: {
        mode: 'template',
        template:
          'card_id={{kanban_task.id}} titulo={{kanban_task.title}} etapa_id={{kanban_task.board_step_id}} valor={{kanban_task.value}}',
      },
    },
    {
      ...common,
      name: 'add_product_to_deal',
      label: 'Adicionar produto ao negocio',
      description:
        'Adiciona um produto do catalogo ao negocio, com a quantidade. O preco vem do catalogo e o valor do negocio passa a ser a soma das linhas. Use o card_id de "Ver negocio da conversa" e o id de "Buscar produtos".',
      method: 'POST',
      urlTemplate: `${CHAT}/api/v1/accounts/1/kanban/cards/{{card_id}}/items`,
      body: {
        mode: 'kv',
        rows: [
          { key: 'product_id', value: '{{product_id}}' },
          { key: 'quantity', value: '{{quantity}}' },
        ],
      },
      inputSchema: {
        card_id: { type: 'integer', required: true, description: 'Id do card (de Ver negocio da conversa).' },
        product_id: { type: 'integer', required: true, description: 'Id do produto (de Buscar produtos).' },
        quantity: { type: 'number', required: true, description: 'Quantidade na unidade do produto.' },
      },
      outputSchema: {
        mode: 'template',
        template: 'Linhas atualizadas. Valor do negocio em centavos: {{payload.value_cents}}; produtos no negocio: {{payload.items_count}}',
      },
    },
  ];
  const created = [];
  for (const tool of tools) {
    const response = await agents('tools', 'POST', tool);
    const id = response.tool?.id ?? response.id;
    created.push(id);
    console.log('tool:', tool.label, '->', id);
  }

  // 4. grants: the natives the agent needs, named one by one (an empty `enabledTools` means NONE), plus the three HTTP tools.
  // The PUT replaces the whole set.
  const natives = [
    'handoff_to_human',
    'private_note',
    'set_custom_attribute',
    'set_labels',
    'resolve_conversation',
    'kanban_move_card',
    'update_kanban_task',
    'skip_reply',
    'calculator',
    'get_current_time',
  ];
  const current = await agents('agents/2/tool-selections');
  await agents('agents/2/tool-selections', 'PUT', {
    grants: [{ source: 'NATIVE', enabledTools: natives }, ...created.map(id => ({ source: 'HTTP', toolDefinitionId: String(id) }))],
    expectedUpdatedAt: current.agentUpdatedAt,
  });
  console.log('grants set on agent 2');
})().catch(error => {
  console.error('FAILED', error.message);
  process.exit(1);
});
