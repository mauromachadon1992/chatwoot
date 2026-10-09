# Sprints pós-staging (S9 a S15) e a subida de produção

Ordem sugerida, cada sprint com objetivo, entregas, aceite e dependências. O "pronto" de cada uma segue a Definition of Done do
`ROADMAP.md` (seção 2): spec primeiro, `run.sh check` verde, tela vista em claro, escuro e 390px, contrato e hash iguais nos dois
repositórios quando a capacidade muda (`contracts/protocol.md`). Plano de produção: `PRODUCTION.md`.

| Sprint | Tema | Depende de | Ganho no dia a dia |
| --- | --- | --- | --- |
| S-P | Produção do zero (`PRODUCTION.md`): backup, teste com número pessoal, go/no-go | decisões do dono | sair da staging |
| S9 | Fonte do catálogo (nativa ou por HTTP) | S-P não bloqueia | não orçar o que não dá para entregar |
| S10 | Piloto de negócios automáticos | S-P | todo contato vira negócio sem digitar |
| S11 | Negócio parado: o Flow avisa o agente | S10 (dados do piloto) | menos negócio esquecido |
| S12 | Perdido com motivo e tarefas pelo agente, ponta a ponta | contrato atual | funil fecha sozinho com histórico |
| S13 | Passagem para humano: filtro, aviso e selo de estado | S-P | ninguém espera sem saber |
| S14 | Orçamento em PDF | S9 (preço/validade) | orçamento com cara de documento |
| S15 | Avaliação do agente (conversas de teste) | S12 | mudar o prompt sem medo |
| S-UX | Consistência de tela (Chatwoot e Agents) | em paralelo | menos atrito |

## S9: fonte do catálogo

**Decisão de desenho:** o catálogo passa a ter um **provedor** por conta, escolhido em Configurações do Kanban:
`native` (a tabela `flow_kanban_products`, como hoje) ou `http` (um serviço do cliente, como o `wsac-gateway`). O agente continua
a ver **uma só** rota (`GET kanban/products`) e não sabe qual provedor responde, então o toolpack não muda.

- **Contrato do provedor HTTP** (documento novo em `contracts/`, versionado): `GET {base}/products?q=&page=` →
  `{items:[{sku,name,unit,price_cents,available,available_quantity?,lead_time_days?}], next_page?}` e
  `GET {base}/products/:sku` para o preço e a disponibilidade na hora de orçar. Autenticação por cabeçalho guardado cifrado;
  HMAC opcional; só HTTPS público (a mesma trava SSRF dos webhooks). Tempo limite de 3 s, uma tentativa, cache de 60 s por
  consulta.
- **Falha do provedor:** o Flow responde ao agente `503 catalog_unavailable` (nunca preço velho sem aviso) e o prompt manda dizer
  que confirma o preço com um atendente; um aviso aparece para o administrador.
- **Linhas do negócio:** gravam `sku`, nome, unidade e preço **no momento do orçamento** (já é assim); com `available=false` o
  Flow recusa a linha (`422 unavailable`) e o agente oferece alternativa.
- **Adaptador do `wsac-gateway`** como primeiro provedor, com o mapeamento de campos dele.
- **Aceite:** com o provedor HTTP simulado fora do ar, o agente não inventa preço; produto indisponível não entra no negócio; a
  troca nativo↔HTTP não muda nada no toolpack; testes de contrato do provedor (fake server) rodam no CI.

## S10: piloto de negócios automáticos

- **Escolher** o board de vendas e a caixa-piloto (decisão 2 do ROADMAP; o dono define), ligar `auto_create` na conta e a regra
  `auto_create {enabled, inbox_ids}` no board.
- **Medir 2 semanas:** negócios criados sozinhos, % com contato certo, % com produto, tempo até o primeiro retorno, falsos
  positivos (conversa que não é venda). Relatório no próprio Kanban (já existe o funil).
- **Aceite:** meta definida antes (por exemplo ≥90% dos negócios automáticos com contato correto); decisão registrada de ampliar
  ou não para outras caixas.

## S11: negócio parado, o Flow avisa o agente (decisão 12, opção 1)

Só entra se o piloto da S10 mostrar negócios que o agente não retoma sozinho.

- Ferramenta HTTP do agente que registra `conversation_ref` no vínculo da conversa; ação de regra `nudge_agent` que envia
  `{event_id, conversation_ref, text}` assinado no formato do agents, por um remetente próprio (`FLOW_AGENTS_BASE_URL` numa lista
  explícita; a trava SSRF dos webhooks continua estrita).
- Respeita a janela de 24 h do WhatsApp (o agente decide; Flow registra "ignorado").
- **Aceite:** negócio parado com conversa registrada gera **uma** mensagem do agente; reenvio do mesmo `event_id` age uma vez;
  board invisível não vaza.

## S12: perdido com motivo e tarefas pelo agente

- Rotas por conversa (o agente nunca informa id de card), capacidades novas no contrato: `deal.lose` (`POST …/deal/lose
  {lost_reason_id, note?}` com a lista de motivos em `GET kanban/lost_reasons`), `deal.tasks` (`POST …/deal/tasks {title,
  due_at}`), e `deal.stage` se faltar (mover por nome de etapa).
- Toolpack `flow-deal-actions` no agents (mesma disciplina do `flow-products`), verificado contra o contrato.
- **Aceite (teste ponta a ponta na staging):** o agente marca um negócio como perdido com motivo, agenda uma tarefa e a conversa
  segue; histórico com `actor_kind: agent_bot`; motivo de outra conta recusado; roteiro vira `custom/script/e2e-staging.sh`.

## S13: passagem para humano

- **Estado explícito:** conversa `pending` com agente = "com o agente" (selo atual); depois do `handoff_to_human` = "aguardando
  humano" (selo âmbar com ícone diferente e texto), e some quando um humano responde.
- **Filtro** no Kanban e atalho "Aguardando humano" (cards com conversa nesse estado, mais antigos primeiro).
- **Aviso:** notificação ao responsável do negócio (e à fila, se não houver) no momento da passagem, com o resumo que o agente
  escreveu na nota privada; opcional e-mail.
- **Aceite:** o agente passa a conversa → em menos de 5 s o card muda de estado e a pessoa certa é avisada; um humano responde → o
  estado some; teste de componente e de API.

## S14: orçamento em PDF

- Geração no servidor a partir do **mesmo** `QuotePreview` (um só cálculo): modelo A4 com marca da conta (logo do white label),
  linhas, descontos, total, validade e condições; endpoint `GET …/deal/quote.pdf` e anexo na conversa (documento no WhatsApp).
- Escolher a biblioteca (Prawn ou renderização HTML→PDF) com um teste de tamanho/tempo; texto selecionável, fonte embutida.
- **Aceite:** o PDF tem os mesmos números do texto (teste que compara), abre no celular, e o agente consegue enviá-lo pela
  ferramenta HTTP.

## S15: avaliação do agente

- **Conjunto de conversas** (YAML versionado em `flow-agents-ee/custom/evals/`): preço, desconto, entrega, reclamação, produto
  inexistente, fora da janela de 24 h, pedido de humano, tentativa de induzir (preço absurdo, "ignore as instruções").
- **Executor:** cria conversa na staging, injeta as mensagens, espera as respostas e **pontua por regras** (preço bate com o
  catálogo, não prometeu o que não pode, passou para humano quando devia, ferramenta certa chamada) mais um juiz de modelo para o
  tom; relatório com custo.
- **CI:** rodar a avaliação manualmente antes de trocar o prompt ou o modelo e guardar o resultado na release.
- **Aceite:** linha de base registrada; mudar o prompt mostra a diferença por caso.

## S-UX: consistência de tela

Achados desta rodada (telas vistas com o ambiente de desenvolvimento):

- Chatwoot, barra do Kanban: em 1280px os filtros e as ações quebram em três linhas (136px de cabeçalho). Abaixo de `2xl` mover
  filtros para o popover que o celular já usa.
- Chatwoot, colunas: o total da coluna só aparece quando é maior que zero e desalinha os cards entre colunas (corrigido: a linha
  do valor agora é sempre mostrada, `R$ 0` quando vazio).
- Agents: a página Componentes mistura cartões com contorno (estado vazio) e blocos tonais (ferramentas nativas): escolher um e
  aplicar na camada `custom/ui/flow.css`.
- Agents e Chatwoot: unificar o vocabulário de estados (ativo, pausado, aguardando humano) e a ordem das ações; revisar
  `PRODUCT.md` e `DESIGN.md` com os tokens que valem para os dois produtos.
- Rodar o Impeccable em cada tela principal depois de cada camada, em claro, escuro e 390px, e arquivar o relatório na release.
