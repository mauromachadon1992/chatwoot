# Contrato Kanban "Pro" v1: o que o fazer.ai agents exige do Chatwoot

Fonte única, copiada nos dois repositórios (`flow-agents-ee` e `mauromachadon1992/chatwoot`).
Reconstruído **só do código aberto do Agents** (`src/modules/chatwoot/client.ts`, `kanban.ts`,
`graph/tools/native.ts` e a fixture de `tests/modules/chatwoot-kanban.test.ts`). Não vem do código do Pro.

Mudou aqui? Atualize `pro-kanban.v1.schema.json` e `CONTRACT.sha256` (`bun custom/script/contract-hash.ts --write`)
**nos dois repositórios**, na mesma semana. Só mudança aditiva dentro da v1.

Autenticação: cabeçalho `api-access-token` do administrador. Prefixo `/api/v1/accounts/:account_id`.
Conversa sempre por **display id**. Dinheiro: `value` é número na moeda da conta.

## Operações

| # | Método do Agents | Requisição | Resposta |
| --- | --- | --- | --- |
| 1 | `listKanbanBoards` | `GET /kanban/boards` | lista de quadros (array, `{payload}` ou `{boards}`) |
| 2 | `createKanbanBoard` | `POST /kanban/boards` `{board:{name,…}}` | quadro (`id`, `name`), nu ou em `{payload}` |
| 3 | `updateKanbanBoard` | `PUT /kanban/boards/:id` `{board:{…}}` | quadro |
| 4 | `listKanbanSteps` | `GET /kanban/boards/:id/steps` | `stepList` do schema; `cancelled: true` = etapa de perda |
| 5 | `createKanbanStep` | `POST /kanban/boards/:id/steps` `{step:{name,color?,description?,cancelled?}}` | etapa |
| 6 | `setBoardInboxes` | `POST /kanban/boards/:id/update_inboxes` `{inbox_ids}` | 2xx, idempotente |
| 7 | `setBoardAgents` | `POST /kanban/boards/:id/update_agents` `{agent_ids}` | 2xx, idempotente |
| 8 | `listKanbanTasks` | `GET /kanban/tasks[?board_id=]` | lista de `card` (array, `{payload}` ou `{tasks}`) |
| 9 | `createKanbanTask` | `POST /kanban/tasks` `{task:{title,board_id,board_step_id,conversation_id?,…}}` | `card` |
| 10 | `moveKanbanTask` | `POST /kanban/tasks/:id/move` `{board_step_id, insert_before_task_id?}` | `card` |
| 11 | `getKanbanTask` | `GET /kanban/tasks/:id` | **`card` nu, sem envelope** |
| 12 | `setKanbanTaskCustomAttributes` | `PATCH /kanban/tasks/:id` `{task:{custom_attributes}}` | `card`; o Agents faz o merge antes, o servidor **atribui** |
| 13 | `setKanbanTaskLabels` | `PATCH /kanban/tasks/:id` `{task:{labels:[…]}}` | `card`; **substitui** o conjunto todo |
| 14 | `updateKanbanTask` | `PATCH /kanban/tasks/:id` `{task:{title,description,priority,start_date,due_date}}` | `card`; `null` limpa descrição e datas; início ≤ prazo |
| 15 | `kanbanTaskForConversation` | `GET /conversations/:display_id` | `conversation` do schema: `kanban_task` é um `card` ou `null` |

## Regras

- **Superconjunto.** O servidor pode devolver campos a mais; nunca pode faltar um campo `required` do schema
  (use `null`, `[]` ou `{}`).
- **Um cartão por conversa** (o `kanban_task`): um só cartão aberto vinculado é ele; vários abertos, o mais
  recentemente atualizado; só fechados, `null`.
- `status` deriva do tipo da etapa (`open`, `won`, `lost`). `cancelled` na etapa é `stage_type == lost`.
- `kanban_task` **não** vai em payload público (widget, push para clientes).
- Escritas do Agents devem aparecer no histórico do negócio com o ator "agente de IA".

## Não vinculado a este contrato

Corpos internos de criação de quadro e de etapa além de `name`, `color`, `description` e `cancelled`;
o envelope exato de `GET /kanban/boards`. O harness (`custom/harness/`) mede o que o servidor real aceita.
