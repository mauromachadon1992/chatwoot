# Extensões Flow v1: o que o Chatwoot custom EE oferece além do dialeto Pro

Fonte única, copiada byte a byte nos dois repositórios (`flow-agents-ee` e `mauromachadon1992/chatwoot`) e coberta pelo
`CONTRACT.sha256`, junto com `pro-kanban.md`, `pro-kanban.v1.schema.json` e `protocol.md`.

O dialeto Pro (`pro-kanban.md`) é o que o cliente do Agents **exige**. Este documento é o que o Flow **acrescenta** e que o agente
alcança por **ferramentas HTTP declarativas** (decisão ADR-3: nenhum código novo no `src/` do Agents). Mudou aqui? Siga o `protocol.md`.

Prefixo `/api/v1/accounts/:account_id`. Autenticação: cabeçalho `api-access-token` do usuário de serviço do agente
(`rake flow:kanban:agent_bot`), administrador por papel. Conversa **sempre por display id**. Dinheiro em **centavos inteiros**.

## Descoberta: nada é presumido, tudo é anunciado

`GET /kanban/settings` responde `{payload: {currency, api_version, dialect, capabilities: [...]}}`. Uma extensão só existe se a
sua capacidade está na lista; quem chama (uma ferramenta, um script) verifica antes. Capacidades anunciadas (v1):

| Capacidade | Documento | O que anuncia |
| --- | --- | --- |
| `boards.read`, `boards.write`, `boards.bindings`, `steps.read`, `steps.write` | `pro-kanban.md` | operações 1 a 7 |
| `tasks.read`, `tasks.create`, `tasks.move`, `tasks.update` | `pro-kanban.md` | operações 8 a 11 e 14 |
| `conversation.kanban_task` | `pro-kanban.md` | operação 15 (`kanban_task` na conversa) |
| `webhook.kanban_task` | este | `conversation.kanban_task` também nos `webhook_data` de saída |
| `tasks.value_attribute` | este | o atributo reservado `deal_value` |
| `products.read` | este | catálogo de produtos |
| `deal.items` | este | linhas de produto do negócio da conversa |

```json flow-extensions
{
  "version": 1,
  "announced": [
    "boards.read", "boards.write", "boards.bindings", "steps.read", "steps.write",
    "tasks.read", "tasks.create", "tasks.move", "tasks.update", "tasks.value_attribute",
    "products.read", "deal.items", "conversation.kanban_task", "webhook.kanban_task"
  ],
  "routes": [
    { "id": "settings", "method": "GET", "path": "/kanban/settings" },
    { "id": "products.search", "method": "GET", "path": "/kanban/products", "requires": "products.read" },
    { "id": "deal.show", "method": "GET", "path": "/kanban/conversations/:display_id/deal", "requires": "deal.items" },
    { "id": "deal.items.set", "method": "POST", "path": "/kanban/conversations/:display_id/deal/items", "requires": "deal.items" },
    { "id": "deal.items.remove", "method": "DELETE", "path": "/kanban/conversations/:display_id/deal/items/:product_id", "requires": "deal.items" }
  ]
}
```

## `tasks.value_attribute`: o valor do negócio pelo agente

O cliente do Agents não tem ferramenta para o valor; ele grava atributos do card (`set_custom_attribute`, escopo `task`). A chave
reservada **`deal_value`** em `custom_attributes` (`PATCH /kanban/tasks/:id`) vira o valor do negócio: um valor digitado
(`"3.420,00"`, `"R$ 10"`, `1200`) é lido pelo `MoneyParser`. O atributo permanece como enviado. O valor do negócio **não muda, e o pedido não falha**, quando: o texto
não é um valor, o valor é negativo ou acima do teto (10 bilhões), o negócio tem produtos (o valor é a soma das linhas) ou o valor já é
igual ao atual.

## `products.read`: o catálogo

`GET /kanban/products?q=<nome ou SKU>&active=true&page=<n>` responde
`{payload: [{id, name, sku, unit, price_cents, active}], meta: {count, page, per_page: 25}}`. A busca é no servidor.

## `deal.items`: as linhas de produto do negócio da conversa

O agente conhece a conversa, não o card: o servidor resolve **o negócio aberto mais recente de um board que o chamador vê** (a regra
de `kanban_task`). O agente nunca informa um id de card.

| Rota | Corpo | Resposta |
| --- | --- | --- |
| `GET …/conversations/:display_id/deal` | | `{payload: card}` com `items` |
| `POST …/conversations/:display_id/deal/items` | `{product_id: inteiro, quantity: número > 0}` | `{payload: card}` |
| `DELETE …/conversations/:display_id/deal/items/:product_id` | | `{payload: card}` |

`card` é o mesmo da leitura do negócio, com `value_cents`, `items_count` e `items: [{id, product_id, name, sku, unit,
quantity (texto), unit_price_cents, discount_percent (texto), total_cents}]`.

Regras (invariantes; a spec do Chatwoot as prova):

- **O preço é do catálogo e o desconto é zero.** `unit_price_cents` e `discount_percent` enviados são ignorados: só a quantidade é do agente.
- **Uma linha por produto.** `POST` de um produto que já está no negócio **substitui** a quantidade; não soma.
- No máximo **50 linhas**. Quantidade acima de zero e até 999.999.999.
- O valor do negócio passa a ser a soma das linhas; o histórico registra `value_changed` com `actor_kind: agent_bot`.

Erros: `404` (conversa inexistente; sem negócio aberto, com `{message}`; produto desconhecido, inativo ou de outra conta; produto fora do
negócio no `DELETE`), `422` (quantidade inválida; mais de 50 linhas), `401` (chamador sem acesso à conversa).

## Compatibilidade

Só mudança **aditiva** dentro da v1: um campo novo na resposta, uma capacidade nova, uma rota nova. Remover ou mudar o sentido de algo
é a v2, anunciada por uma capacidade nova com a antiga mantida por uma versão. O servidor pode acrescentar campos; o cliente ignora os
que não conhece.
