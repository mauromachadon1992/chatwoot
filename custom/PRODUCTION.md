# Produção do zero: plano de subida (Chatwoot EE + Agents EE)

Decisão do dono (2026-10-09): a produção nova sobe **do zero**, com todos os segredos gerados de novo. A produção atual
(`chatwoot-baileys` e `agents` v1.36.0, projeto `infra-compartilhada`) **não é tocada** até o corte; ela é o rollback.

## 0. Antes de começar (decisões e pré-requisitos)

| Item | Estado | Quem |
| --- | --- | --- |
| Os dados da produção atual (contatos, conversas, histórico) **não vão** para a nova? Se algum deve ir, definir antes: exportar contatos em CSV pelo Chatwoot, ou migrar o banco (fora deste plano) | **pendente: confirmar** | dono |
| Domínios novos (Chat e Agents) e DNS apontando para o Coolify | pendente | dono |
| Licença Chatwoot Inc. para o `enterprise/` em produção (`INSTALLATION_IDENTIFIER`) | pendente | dono |
| Revisão jurídica da combinação das licenças (`custom/LICENSE`) | pendente | dono |
| `docker login ghcr.io` no servidor do Coolify com token `read:packages` (os pacotes são privados) | a confirmar | dono |
| Número de WhatsApp de produção e quem faz o pareamento (QR) | pendente | dono |

## 1. Infraestrutura (Coolify, ambiente `production` do projeto `atendimento`)

- Dois serviços novos, cada um com **o próprio** PostgreSQL (pgvector no Agents) e Redis, **sem** compartilhar com a
  `infra-compartilhada`: `chatwoot-production` (base: `custom/docker/coolify.staging.compose.yaml`, trocando host, `FRONTEND_URL`
  literal, nome do banco e `CHATWOOT_HUB_SYNC=true` só depois da licença) e `agents-production`.
- Segredos: todos `SERVICE_*` gerados pelo Coolify (nenhum no compose, nenhum neste repositório). `SECRET_KEY_BASE` novo.
- Imagens por **tag imutável**: `chatwoot:flow-chat-vX.Y.Z` e `agents-ee:flow-vX.Y.Z` (nunca `latest`).
- Volumes nomeados para `storage` (Chatwoot) e para os dados do Agents; healthcheck dos dois como na staging.
- `MAILER_SENDER_EMAIL` e `RESEND_API_KEY` reais (senão não há e-mail de convite nem recuperação de senha).

## 2. Backup e restauração (sem isso não há go-live)

1. Dump diário do PostgreSQL de cada serviço (agendador do Coolify ou `pg_dump` em tarefa agendada), retenção de 14 dias, cópia
   **fora** do servidor.
2. Backup do volume `storage` (anexos, imagens do login) semanal.
3. **Ensaio de restauração obrigatório** na staging: restaurar o último dump num serviço limpo e conferir login, uma conversa e
   um card. Registrar a data no `BACKLOG.md`.
4. O pareamento do Baileys vive no banco `whatsapp_connector` do Chatwoot: entra no dump; sem ele o número precisa de novo QR.

## 3. Subida e configuração (ordem)

1. Subir `chatwoot-production`; criar o super admin e a conta; aplicar a identidade (`rake flow:identity:apply`).
2. Subir `agents-production`; as migrações rodam no boot (banco novo: nada a migrar).
3. Criar o usuário de serviço (`POST accounts/:id/agents`, depois `rake "flow:kanban:agent_bot[EMAIL]"`) e ligar o Agents ao
   Chatwoot (`PATCH /v1/chatwoot/deployment {adminToken}` com o token **do usuário de serviço**, nunca o de uma pessoa).
4. Cofre do Agents: chave do modelo; criar o agente, o prompt (inclui `set_custom_attribute` escopo `task` chave `deal_value`
   só se não usar as ferramentas do negócio), vincular à caixa, `mode: production`.
5. `bun custom/script/apply-toolpack.ts --apply` (chaves e tokens só por variável de ambiente).
6. Board de vendas com etapa de ganho e de perdido, catálogo de produtos, criação automática de negócios **ligada só na caixa-piloto**.

## 4. Teste com o número pessoal do dono (antes de qualquer cliente)

Na **staging** primeiro, depois na produção, com a caixa do WhatsApp (Baileys) e o número do dono:

1. Criar a caixa WhatsApp (Baileys) e parear pelo QR na interface (só a pessoa dona do número faz isso).
2. Mandar do celular: pedido com produto e quantidade → o agente responde com o orçamento do servidor → "aprovado" → confirmação
   → o card vai para Ganho e a conversa é resolvida. Conferir `actor_kind: agent_bot` no histórico.
3. Casos: pedir produto que não existe; pedir desconto; reclamar (esperado: passar para humano e o selo sair do card); mandar
   áudio e imagem; ficar mais de 24 h sem responder (janela do WhatsApp: o agente não pode escrever fora dela).
4. Resultado e custo por conversa no painel do Agents; apagar os dados de teste.

## 5. Go / no-go (todos marcados)

- [ ] Backup restaurado com sucesso (item 2.3)
- [ ] Teste com WhatsApp real passou (seção 4)
- [ ] Segredos só no Coolify; nenhum em chat, repositório ou log
- [ ] Licença Chatwoot Inc. aplicada; revisão jurídica feita
- [ ] Monitor externo no `/api` e no `/flow/version` com alerta (qualquer serviço de uptime)
- [ ] Telas conferidas em claro, escuro e celular (relatório do Impeccable sem achados nossos)
- [ ] Plano de rollback lido por quem faz o corte

## 6. Corte e rollback

- Um número de WhatsApp só conecta a **uma** instalação por vez: o corte é uma janela curta (parar o Baileys da produção
  atual, parear na nova, testar uma mensagem). Avisar a equipe antes.
- Rollback: se a nova falhar na janela, **parar o Baileys da nova e religar o da produção atual** (que continua intacto) e, se
  preciso, parear de novo lá. Por isso a produção atual só é desligada **depois de 7 dias** sem incidente.
- Promover versão depois do corte: nova tag → trocar a tag da imagem → observar `/flow/version` e o painel por 30 minutos; voltar
  é trocar a tag anterior.
