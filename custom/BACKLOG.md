# BACKLOG.md: read this first (for an LLM session; humans: ROADMAP.md is the plan, this is the state)

Purpose: start a session with the base context and the next actions, without re-deriving them.
Keep it true: when you finish an item, delete it here and record the fact in README.md or ROADMAP.md.
Last verified: 2026-10-08 on `feat/kanban` @ `22a11292f`. Facts older than a month: re-verify before use.
Never write a secret here (tokens, keys, passwords). Credentials seen in a chat are exposed; say "revoke", never copy.

## 0. CONTEXT_BASE (facts, not plans)

### 0.1 What this is
- Owner: Mauro (pt-BR speaker; answer in Portuguese; mauromn1992@gmail.com). Style: direct, verify every detail, one
  batched visual round (light, dark, 390px) plus at most one confirm round. Never infer pronouns.
- Product: "Flow Agents" = a Chatwoot fork (`github.com/mauromachadon1992/chatwoot`, branch `feat/kanban`) that adds a
  Kanban of deals in `custom/`, plus a private copy of the fazer.ai agents (`mauromachadon1992/flow-agents-ee`,
  Free edition, Apache 2.0, kept identical to upstream except `custom/`, `.github/`, README).
- Goal of "phase P": the fazer.ai agents' unchanged `ChatwootClient` works against Flow's Kanban (the "Pro dialect").
  Status: **done, 16/16 harness checks on dev, on the built image, and on staging**; the agents' own 78 Kanban tests pass.

### 0.2 Repos and paths
- Chatwoot working copy: WSL Ubuntu `~/chatwoot` = `\\wsl.localhost\Ubuntu\home\mauro\chatwoot`. Kanban code: `custom/`
  (Rails engine: `Custom::Kanban::*`, tables `flow_kanban_*`, migrations in `custom/db/migrate`, specs in
  `spec/custom/kanban`, locales `custom/config/locales/flow_kanban.*.yml`). Frontend: `app/javascript/dashboard/routes/dashboard/flowKanban/`,
  strings `app/javascript/dashboard/i18n/fazer-ai/locale/{en,pt_BR,es}/flowKanban.json`. UI rules: `DESIGN.md` (repo root).
- Upstream touches are minimal one-line hooks, listed in `custom/README.md`. `prepend_mod_with` resolves `Custom::<Const>`.
- Agents repo clone (read/merge only): scratchpad `agents-ee-repo` (Windows). `core.autocrlf` is false there; **a tar from
  `git archive` can show CRLF if autocrlf is true; blobs on `main` are LF**. Contract: `custom/contracts/{pro-kanban.md,
  pro-kanban.v1.schema.json,CONTRACT.sha256}` identical in both repos (hash `a7382804…`); `.gitattributes` keeps LF.
- Helper scripts: `~/flow-tools/*.sh` (WSL). Key ones: `run.sh check` (gate), `run-agents-harness.sh` (`TARGET=dev|ee-local`),
  `run-harness-remote.sh <base> <acct> <conv> <inbox> <agent>` (token via env `CT` only), `agents-own-tests.sh`,
  `final-harness.sh` (ee-local), `commit-*.sh`, `build-agents-ee.sh <sha>`, `wait-*.sh`.

### 0.3 Environment quirks (cost me tokens before)
- Shell is Git Bash/PowerShell on Windows; WSL via `MSYS_NO_PATHCONV=1 wsl -d Ubuntu -u mauro -- bash <script>`. **Quoted
  heredocs through bash often fail: write a script file with the Write tool.** WSL has **no `node` and no python**; Git Bash
  has node; run Node in the container with `~/flow-tools/run-node.sh`. Windows has no python.
- Pass secrets to WSL only through the environment (`WSLENV=CT`), never in a file or an argument.
- Foreground `sleep` is blocked: wait with an until-loop in a background command, or a script that polls.
- Routes change needs `restart-dev.sh`; browser runs need `clear-dev-sessions.sh`.
- Commits go through the container hook: `docker compose exec -T -u 1000:1000 -e HOME=/tmp rails git commit -F .git/<msg>`
  (message ends with the attribution line the harness gives). Push from WSL **hangs**; push with Windows git:
  `git -c safe.directory='%(prefix)///wsl.localhost/Ubuntu/home/mauro/chatwoot' -C \\wsl.localhost\Ubuntu\home\mauro\chatwoot push origin feat/kanban`.
- Never run `rubocop` over `git ls-files` globs (hits the whole repo): use `custom spec/custom`.
- Running migrations makes `annotate` rewrite upstream models (`app/models/**`, `enterprise/**`): `git checkout` them before committing.
- Containers leave root-owned files: clean with `docker run --rm -v ~/:/h alpine rm -rf /h/<dir>`.
- Image build (~5 min): `custom/docker/build-ee feat/kanban` detached (`setsid nohup … & disown`), wait with `wait-build2.sh`,
  publish with `custom/docker/publish-ghcr` (immutable tags `<ver>-<sha>-ee`, `<sha>-ee`, moving `<ver>-ee`, `latest-ee`).
- Harness `bun install` can fail on transient DNS and leave a half `node_modules`: `rm -rf ~/agents-ee-work` (alpine) and rerun.
- The permission classifier blocks some actions (credential use, Coolify writes, deletes, ghcr publish). The user may say
  "tente de novo"; **do not work around a denial, stop and explain**.

### 0.4 Gates (Definition of Done)
`~/flow-tools/run.sh check` = rspec (353 ex, 0 failures) + vitest (123) + eslint (0 errors) + design-audit (0 findings),
plus `rubocop custom spec/custom`. UI work: follow `DESIGN.md`; load skills `impeccable` and `designing-user-interfaces`.

### 0.5 Code facts that bite
- Pro dialect: a Pro "task" is a Flow Card, a "step" is a Stage. `GET /kanban/tasks` = Pro deals; the old "my tasks" is
  `/kanban/my_tasks`. Rails `wrap_parameters` is off for the Kanban API; `{board:}`/`{step:}`/`{task:}` root keys are the
  dialect only when really sent (a board made with the root key gets **no default stages**; undecided, see B-09).
- `PATCH /kanban/tasks/:id` accepts only `title description priority start_date due_date custom_attributes labels`
  (`UPDATABLE` in `compat/tasks_controller.rb`). **There is no `value`**, so an agent cannot set a deal's amount (see B-02).
- Card events carry `actor_kind` user | agent_bot | rule | system. `agent_bot` only for the service user
  (`Custom::Kanban::ServiceUser`, flag `custom_attributes['flow_service']='agent_bot'`, created only by
  `rake flow:kanban:agent_bot[EMAIL]`; blocked from webhooks, imports, automations by `HumanAdministrator`).
- Account features (`flow_kanban_features`: auto_create, stale_alerts, webhooks, ai_summary): `auto_create` and `ai_summary`
  default **off**; toggled by a super admin in `/super_admin` → Accounts → edit. Auto-create also needs the board rule
  (`PUT boards/:id {auto_create:{enabled,inbox_ids}}`).
- Outgoing conversation webhooks carry `conversation.kanban_task` (title, stage, value) to every receiver.
- Automations stop at 30 runs per deal per hour. Webhook HMAC over `"<ts>.<body>"`, SSRF ranges blocked.

### 0.6 Environments
- Dev: docker compose in `~/chatwoot`. ee-local: `custom/docker/ee-local up` (built image, throwaway data).
- Staging (Coolify `https://vps.freitascasaeconstrucao.com.br`, project `atendimento`, env `staging`):
  - `chatwoot-staging` service uuid `5brvjno3ifszb3dm4xweecsy`, host `chat-hml.freitascasaeconstrucao.com.br`, image
    `ghcr.io/mauromachadon1992/chatwoot:4.18.0-a84b8562d-ee` via env `FLOW_IMAGE_TAG` (B-02 and the card tabs). Compose: `custom/docker/coolify.staging.compose.yaml`.
    **`FRONTEND_URL` is a literal in the compose (Coolify restores compose values on restart); env overrides do not stick.**
  - `agents-staging` uuid `oig9l2odn1nkhf7fuvf4sxls`, host `agentes-hml.freitascasaeconstrucao.com.br`, image
    `ghcr.io/mauromachadon1992/agents-ee:6b441a4` (agents-ee main, = upstream v1.39.0 + Flow files). Own Postgres (pgvector) and volume.
  - Staging data left from tests: Chatwoot account 1; boards 1 "Teste" (user's), 2-3 "harness …", 4 "Vendas e2e"; inboxes 2
    `harness-inbox`, 3 `e2e-vendas`; conversations 13-19; agents-ee tenant 1, agent 1 and 2, vault entry 1 (DeepSeek key).
    Agent 2 "Vendedor Concreto (e2e)" is bound to inbox 3, mode `production`, model `deepseek-flash` (the id DeepSeek lists).
- Production (**do not touch without explicit go-ahead**): `chatwoot-baileys` (Chatwoot + Baileys) and `agents` (official
  `ghcr.io/fazer-ai/agents:v1.36.0`, three versions behind). Shared infra in project `infra-compartilhada`.
- Coolify API (v4.4.2): `Authorization: Bearer <token>`; services are `services/<uuid>` (`/envs` PATCH, `/restart` and `/start` are
  POST, compose is `PATCH {docker_compose_raw: <base64>}`). No exec endpoint, but **scheduled tasks run a command in a service
  container**: `POST services/<uuid>/scheduled-tasks {name, command, frequency:"* * * * *", container:"rails"}`, read
  `…/<task>/executions` (field `message`), then `DELETE` the task at once (it repeats every minute). Output carries
  secrets: do not echo it unmasked. Needs the user's go-ahead each time.
- Creating the service user: `POST /accounts/1/agents {name,email,role:"administrator"}` (SuperAdmin token) → then, in the
  container, `rake flow:kanban:agent_bot[EMAIL]` **only flags an existing user and prints no token**; the token comes from
  `rails runner 'puts User.from_email(EMAIL).access_token.token'` (write it with `%q()` instead of quotes inside a task).
  Then `PATCH agents /v1/chatwoot/deployment {adminToken}`. A future `CREATE=1` option on the rake would remove two steps.
- Agents API: `https://agentes-hml…/api/v1` with a fleet key + `X-Tenant-Id: 1`. Useful: `GET chatwoot/deployment`,
  `POST chatwoot/instances/1/sync-inboxes`, `PATCH chatwoot/inboxes/:id {agentId}`, `POST vault`, `POST agents`
  (`modelConfig.credentialRef = "vault:<id>"`), `PATCH agents/:id {mode}`. Spec: `openapi.json` in the agents repo.

### 0.7 Behaviour learned from the staging end-to-end test (use it, do not rediscover)
- Chatwoot with an agent bot on the inbox starts conversations **`pending`**; the bot acts only on `pending`; the default
  "Abertas" filter hides them (they show under Pendentes/Todos). A handoff reopens the conversation.
- An agent in `mode: test` does not answer real contacts; use `production`.
- The agent can only touch the card **linked to the conversation** (no create tool): the card must pre-exist (auto-create or a human).
- The agent splits a reply into several public messages and may add a **private note** (`message_type 1`, `private:true`)
  for humans. When counting replies, check `private`.
- API parsing trap: `POST /conversations` returns several `"id"`s; the conversation id is the **last** one (or read it back via the list).
- Result of the e2e: price maths correct, card renamed, priority set, stage moved to "Ganho" on "aprovado". Deal `value` stayed 0.

## 1. NEXT (ordered; each item: why, acceptance)

- **B-01 DONE on staging (2026-10-08):** agents-ee now uses the service user "Agente Flow (servico)" (Chatwoot user id 2,
  `agente-flow-hml@…`, flagged `agent_bot`). Verified: e2e conversation 18 shows `actor_kind: agent_bot` on `stage_moved`,
  `priority_changed`, `attributes_changed`; the token reads boards (200) and gets "not authorized" (401) on webhooks, imports
  and automations. **Left to do:** rotate that token (it was printed in a session log) and repeat the setup for production (B-05).
- **B-02 DONE on staging (2026-10-08):** the agent records the quoted total through the attribute `deal_value`
  (`PATCH kanban/tasks/:id`, Flow-only, capability `tasks.value_attribute`). Verified e2e on conversation 19: 20 m3 fck 30 + pump =
  R$ 12.200,00 stored as the deal value, `value_changed` by `agent_bot`, then "aprovado" moved the card to Ganho. The agent only does it
  because its prompt says: `set_custom_attribute` scope `task`, key `deal_value`, number only. Copy that line into any new agent.
- **B-03 [human] Revoke exposed credentials** (pasted in chat on 2026-10-07/08): Coolify API token, agents fleet key, staging
  Chatwoot SuperAdmin token, DeepSeek key, and the service user's token (rotate: new token, then PATCH the agents deployment). Then remove the vault entry/agents on staging if the key is not renewed.
- **B-04 [human, needs permission] Staging cleanup:** delete boards 2 and 3 (classifier blocked it), `harness-inbox`, conversation 13.
- **B-05 [decision] Production:** promote `chatwoot-baileys` to the Phase P image and move `agents` from v1.36.0 to our agents-ee.
  Needs: migration plan for agents' database (v1.36→v1.39 migrations), backup, rollback tag, user go-ahead. Never self-initiate.
- **B-06 [me] Upstream sync:** wait for fazer.ai agents `v1.40.0` (main has 6 unreleased commits: #1151, #1108, #1128/#1130, sync,
  #1115). Flow: bring the upstream tree into flow-agents-ee `main`, keep `custom/`, `.github/` flow workflows, README, run harness
  + own tests, build and publish `agents-ee:<sha>`. Also review the unmerged branch `chore/merge-upstream-20261008`.
- **B-07 [me] CI for compatibility:** run `agents-own-tests.sh` and the harness in CI on both repos; fail on contract hash drift.
- **B-08 [me] Phase P leftovers:** C5 (Flow-only abilities exposed to the agent), C6 (events to the agent, design open; ROADMAP §7
  decision 12), ROADMAP §7 decisions 9-12.
- **B-09 [decision] `{board:}` root key:** should a board created with the Pro root key get default stages? Compare with a real Pro board.
- **B-10 [me] UX of bot-handled conversations:** decide whether Flow should surface "pending, handled by agent" (a badge or a
  Kanban filter), since agents' work is invisible under the default "Abertas" filter. Use the UI skills and DESIGN.md.
- **B-12 DONE (2026-10-08) card panel in tabs:** `flowKanban/PanelTabs.vue` + `panelTabs.js` (details, value, tasks, conversations, history;
  identity stays above). Verified in light, dark and 390px with `~/flow-tools/shoot.sh` (Playwright image, dev user `visual@flowagents.test`
  created by `visual-seed.rb`, dev DB only). Same pattern fits `BoardSettingsPanel.vue` if it grows (not done).
- **B-13 [decision, then me] Products for the agents.** Finding (2026-10-08): the agents have **no native tool for products or card
  items**. Natives (15): handoff_to_human, private_note, set_custom_attribute, set_labels, resolve_conversation, kanban_move_card,
  update_kanban_task (title, description, priority, dates), set_voice_preference, update_contact, react_to_message, send_image,
  open_case_in_inbox, skip_reply, calculator, get_current_time. The Pro dialect has no items either. Flow already has the data:
  `GET kanban/products?q=&active=true` (25 per page; id, name, sku, unit, price_cents, active; verified 200 with the service token),
  `POST kanban/cards/:card_id/items {product_id, quantity, unit_price_cents?, discount_percent?}` (the deal then equals the sum of its
  lines; `deal_value` is ignored for such a deal), `POST kanban/cards/:id/quote` (message text with the lines).
  Recommended: **HTTP tools on the agent** (`POST /v1/tools`: method, urlTemplate, allowedHosts, headers with `{{secret}}`, `credentialRef`
  vault, inputSchema, responseTemplate), so agents-ee stays identical to upstream (a native tool would conflict at every sync).
  Tools: `search_products(q)`, `add_product_to_deal(product_id, quantity)`, `get_deal_quote()`. **Gap to build in Flow first:** the agent knows
  the conversation (`{{conversation_id}}` fixed field) but not the card id, so add conversation-scoped routes with the same "most recently
  updated open deal" rule as `kanban_task`: `GET kanban/conversations/:display_id/deal` (with lines, total) and
  `POST kanban/conversations/:display_id/deal/items`. Guards: the price always comes from the catalog (the agent cannot send
  `unit_price_cents`), discount capped by a board setting (default 0), quantity cap, one line per product (adding again updates the
  quantity), history event with `actor_kind: agent_bot`, service user only needs `update?` on the card. Later option: one MCP server
  in Flow for products, deals and quote (typed tools, one registration), after the HTTP tools prove the flow. RAG (a knowledge base
  synced from `products/export`) only helps with descriptions, never with price or write. Open question for the user: is the catalog
  source of truth Flow Products or the store ERP through `wsac-gateway` (production bridge for catalog, availability and quote)?
  Accept: e2e on staging: the customer asks for N units of a product, the agent searches, adds the line, the deal value is the catalog
  price times N, and the quote text matches `POST cards/:id/quote`.
- **B-11 [me] Docs:** record the staging topology and the e2e recipe in `custom/README.md` (this file holds the working notes).

## 2. HOW TO START A SESSION (cheapest path)
1. Read this file; do not re-read ROADMAP.md (577 lines) unless an item points at a section.
2. `git log --oneline -5` and `git status --short` in `~/chatwoot` (use the Windows `safe.directory` flag or run via WSL).
3. If you touch code: write the spec first, run `~/flow-tools/run.sh check`, then the harness (`TARGET=dev`).
4. If you touch staging: read-only first (`GET`), state the exact write you will do, expect a classifier denial, stop on denial.
5. Update this file before ending the session: remove done items, add new facts under 0.x with a date.
