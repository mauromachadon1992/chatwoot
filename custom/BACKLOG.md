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
  pro-kanban.v1.schema.json,flow-extensions.md,protocol.md,CONTRACT.sha256}` identical in both repos (one hash `8fd789ba65d5` over the four);
  `.gitattributes` keeps LF. **How the two repos talk: `custom/contracts/protocol.md`** (layers, who changes what, order of a cross-repo
  change, issues/PRs/labels, ladder of proofs). The agents repo has its own `custom/BACKLOG.md` (AG-side state); do not mirror one into the other.
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
    `ghcr.io/mauromachadon1992/chatwoot:4.18.0-a0dcb1877-ee` via env `FLOW_IMAGE_TAG` (B-02, the card tabs, B-13b and the Flow identity, applied with `flow:identity:apply`). Compose: `custom/docker/coolify.staging.compose.yaml`.
    **`FRONTEND_URL` is a literal in the compose (Coolify restores compose values on restart); env overrides do not stick.**
  - `agents-staging` uuid `oig9l2odn1nkhf7fuvf4sxls`, host `agentes-hml.freitascasaeconstrucao.com.br`, image
    `ghcr.io/mauromachadon1992/agents-ee:4deeb6b7` via env `AGENTS_IMAGE` (= AG `main` `ad3dd787` after PRs #14 and #16 were merged, same tree; previous: `1ecbbed3`, then `6b441a4`). Own Postgres (pgvector) and volume.
  - Staging data left from tests: Chatwoot account 1; boards 1 "Teste" (user's), 2-3 "harness …", 4 "Vendas e2e"; inboxes 2
    `harness-inbox`, 3 `e2e-vendas`; conversations 13-21; catalog products 1-3 (Concreto fck 25, fck 30, Bombeamento); agents-ee tenant 1, agent 1 and 2, vault entry 1 (DeepSeek key).
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
- **B-04 [human, denied by the classifier 2026-10-09] Staging cleanup:** delete boards 2 and 3, `harness-inbox`, conversation 13. The owner OK'd it and gave a Coolify token; a read-only scheduled task confirmed the targets (boards 2 and 3 `harness …` with 0 and 1 cards, inbox 2 `harness-inbox` with conversation 13 only) and the delete task was **denied by the auto-mode classifier**, so nothing was deleted. Command (255-char limit on scheduled tasks): `bundle exec rails runner 'Custom::Kanban::Board.where(id: [2,3]).select{|b|b.name.start_with?(%q(harness))}.each(&:destroy);Conversation.where(display_id: 13, inbox_id: 2).destroy_all;Inbox.where(id: 2, name: %q(harness-inbox)).destroy_all'`. Needs a fresh SuperAdmin or administrator token of the staging account (or a Coolify token for a scheduled task running a `rails runner`).
- **B-05 [decision] Production:** promote `chatwoot-baileys` to the Phase P image and move `agents` from v1.36.0 to our agents-ee.
  Needs: migration plan for agents' database (v1.36→v1.39 migrations), backup, rollback tag, user go-ahead. Never self-initiate.
- **B-06 DONE except the staging switch (2026-10-09):** upstream agents `v1.40.2` + 2 commits merged into AG `main` (PR #17, then #18 and #19; `main` = `ad7e8c84`). Harness 16/16, own tests 80/0, CI green. Image `agents-ee:ad7e8c84` built and **published**. **Left:** staging `AGENTS_IMAGE` still `4deeb6b7` (the auto-mode classifier denied the Coolify env write); set it to `ghcr.io/mauromachadon1992/agents-ee:ad7e8c84` and restart `agents-staging`. New additive migrations run on boot: `conversation_type_and_labels`, `inbox_metadata_at`, `llm_usage_cache_creation_1h`. The branch `chore/merge-upstream-20261008` is superseded.
- **B-07 DONE (2026-10-09, merged):** AG PR #18 adds `flow-compat.yml`: the contract hash must equal the one on the public Chatwoot `feat/kanban` (on PRs, pushes and nightly) and the client's own Kanban tests run. Not covered: the real harness in CI (needs a `read:packages` secret for the private image) and a mirror check inside the Chatwoot repo (it cannot read the private AG repo without a PAT secret; its half is `flow_extensions_contract_spec.rb`).
- **B-08 partly done (2026-10-09):** C5 `quote_preview` built (CW commit `4b4951170`): `GET kanban/cards/:id/quote_preview` and the agent's `GET kanban/conversations/:display_id/deal/quote` (capability `deal.quote`), the dashboard dialog reads it, contract hash `e6a2dfc71b9e` in both repos, AG PR #19 adds the tool `get_deal_quote` (merge after #17; staging needs the new Chatwoot image first, then `apply-toolpack.ts --apply`). Settings already announce `api_version` and `capabilities`. **Decisions recorded as taken (the owner may overturn):** §7.9 service user (done, B-01), §7.10 the most recently updated open card (implemented, `ProSerializer.open_card_of`), §7.11 board agents are stored per board (C4 done), §7.12 option 2: no nudge from Flow; the agents' follow-ups plus human tasks (nothing to build; revisit if a pilot shows stalled deals). **Left of C5:** an automated e2e that a test agent marks a deal lost with a reason and schedules a task through HTTP tools (the routes exist; the toolpack covers products and quote only), and the OpenAPI note.
- **B-09 DECIDED (2026-10-09): keep it.** A board made with the `{board:}` root key gets no default stages because the agents' funnel wizard creates its own (`pro_dialect_spec.rb:66` pins both cases). We have no real Pro board to compare with; if one shows Pro adds stages, the spec is the single place to change.
- **B-10 DONE in code (2026-10-09):** each card's linked conversation carries `handled_by_agent` (pending and an active agent bot on the inbox); `ConversationChips.vue` shows a robot in amber and the title "Pending: an AI agent is handling it" (3 locales) instead of the plain dot; spec `card_push_event_data_spec.rb`; no N+1 (`Card::CONVERSATION_PRELOAD`). Not shot in light/dark/390px yet (`~/flow-tools/shoot.sh`), and no Kanban filter (a badge was judged enough). On staging after the next Chatwoot image.
- **B-12 DONE (2026-10-08) card panel in tabs:** `flowKanban/PanelTabs.vue` + `panelTabs.js` (details, value, tasks, conversations, history;
  identity stays above). Verified in light, dark and 390px with `~/flow-tools/shoot.sh` (Playwright image, dev user `visual@flowagents.test`
  created by `visual-seed.rb`, dev DB only). Same pattern fits `BoardSettingsPanel.vue` if it grows (not done).
- **B-13a DONE on staging (2026-10-08): the HTTP tools work end to end** (conversation 20, agent 2). With three HTTP tools the agent
  read its deal (`GET conversations/:id`, template `kanban_task.*`), searched the catalog and added two lines (Concreto fck 25 x12 at
  R$ 480, Bombeamento x12 at R$ 90): the deal value became R$ 6.840,00 from the catalog prices, `value_changed` by `agent_bot`; after
  "aprovado" it set the priority, moved the card to Ganho and resolved the conversation. Recipe now: the toolpack `custom/toolpacks/flow-products.json` of flow-agents-ee, applied by its `custom/script/apply-toolpack.ts` (AG#6, PR #9).
  Gotchas learned: `POST /v1/tools` needs `name` (the identifier) besides `label`; the vault kind `header` with `paramName` injects the
  service token (the model never sees it); the context variables an HTTP tool can use are conversation_id, message_id, contact_*,
  inbox_*, company_name, agent_name, **not the card id** (so the card id comes from a first tool call); `PUT tool-selections`
  replaces the whole set and `enabledTools: []` means **no** native tool (it silently removed move/priority until fixed by listing the
  natives by name). **Known risk, still open (B-13b):** the agent supplies the `card_id`, and the service token reads/writes any card
  it can see (verified: GET of another conversation's card returns 200). Build the conversation-scoped routes below to close it.
- **B-13b DONE on staging (2026-10-08):** `Api::V1::Accounts::Kanban::ConversationDealsController` (16 specs), image
  `4.18.0-6ebd0dc7d-ee`. Verified on conversation 21 with the service token: read the deal of the conversation, add fck 25 x3 while sending
  `unit_price_cents: 1` and `discount_percent: 90` (both ignored: 3 x 480,00), the same product x5 (replaces), a second product, a
  quantity of 0 (422), an unknown product (404), remove by product id, `value_changed` by `agent_bot`. A conversation whose deals are all won or
  lost answers 404 "no open deal" (conversation 20). Decision (a) taken 2026-10-08: the native-tool PR (AG#2) is closed, not merged. The toolpack was merged in AG (PR #9) and applied to the
  staging agent (the earlier tools `get_current_deal` and `add_product_to_deal`, which took a card id, are disabled); conversation 22 proved it.
  Nothing left for B-13b except the catalog decision below.
- **B-13 (decision still open):** is the catalog's source of truth Flow Products or the store ERP through `wsac-gateway` (production
  bridge for catalog, availability and quote)? Native tools were built and not taken (AG PR #2 closed, branch `feat/flow-product-tools` kept: every upstream merge would conflict). A later option: one MCP server in
  Flow. RAG over `products/export` only helps with descriptions.
- **B-14 [decision] The name Flow Chat / Flow Agents beyond the READMEs.** Identity decided 2026-10-08 (display names "Flow Chat" and "Flow Agents", slugs `flow-chat` and `flow-agents` for machines; marks with rising columns; AG PR for issue #13): one contract (`custom/contracts/identity.md`, five SVGs, hash-checked in both repos). flow-chat applies it with `rake flow:identity:apply` (login page row; not yet run on staging, needs the owner OK); flow-agents carries it as its default brand because `PATCH /v1/branding` is Pro (AG branch `feat/flow-identity`). Done 2026-10-08: both READMEs (pt, en) and `custom/README.md` of both
  repos name the product flow-chat / flow-agents, tell the real state and drop fazer.ai's logo; "fazer.ai" stays only as attribution (the
  derivation, upstream links, license and NOTICE, "not official, no support"). **Not done, on purpose:** a blind replace of "fazer.ai". There are
  169 files here and 253 in AG that mention it, and most are not branding: code and paths (`i18n/fazer-ai/locale/` is a code path, imports depend
  on it), upstream URLs and the `upstream` remote, the license and NOTICE (Apache 2.0 and MIT require the notices to stay), upstream docs. What a
  rename may touch, one decision each: the app name and logo in the UI (white label is configuration: `CUSTOM_BRANDING.md`, no code; AG still shows
  the upstream identity, roadmap sprint A0); the image and package names (`ghcr.io/.../chatwoot`, `agents-ee`: published tags are immutable);
  `package.json` names; docs of the upstream. **Open for the owner:** who holds the copyright of `custom/` and under which license (the READMEs
  say only that it derives from the code it extends and changes no terms); Chatwoot Enterprise needs a Chatwoot Inc. license in production and the
  AI deal summary uses Captain.
- **B-11 DONE (2026-10-09):** `custom/README.md` has the section "Staging and the end-to-end recipe" and the notes for `deal.quote` and `handled_by_agent`; this file keeps the uuids and the working notes.

## 2. HOW TO START A SESSION (cheapest path)
1. Read this file; do not re-read ROADMAP.md (577 lines) unless an item points at a section.
2. `git log --oneline -5` and `git status --short` in `~/chatwoot` (use the Windows `safe.directory` flag or run via WSL).
3. If you touch code: write the spec first, run `~/flow-tools/run.sh check`, then the harness (`TARGET=dev`).
4. If you touch staging: read-only first (`GET`), state the exact write you will do, expect a classifier denial, stop on denial.
5. Update this file before ending the session: remove done items, add new facts under 0.x with a date.

## 3. FROM THE AGENTS REPO (one line per change that touches this repo, newest first; written here, never mirrored)
Rule R8 of the AG backlog and section 3 of `custom/contracts/protocol.md`: any AG change that CW depends on, and every CW change the agents depend on, gets one line here and one in the AG backlog, with ids and SHAs.
- 2026-10-08 AG: AG PRs #8 (contract + protocol, `ae47f46`), #9 (toolpack, `a58c933`) and #10 (PR template + labels, `e9f662c`) are **merged** in `flow-agents-ee` `main` (`265bc91` with the backlog); issues #5, #6, #7 closed; none open. The five contract files there are byte-identical to this repo's, hash `8fd789ba65d5` on both sides. The agents code is still the image on staging (`6b441a4`). The branch `claude/jolly-johnson-bq9kim` of this repo is redundant and waits for the owner's OK to be deleted (tips `ed80879c5`, `20522ff53`).
- 2026-10-08 AG: native-tool PR (AG#2) closed, not merged (decision (a)); toolpack `custom/toolpacks/flow-products.json` + `toolpack-check.ts` + `apply-toolpack.ts` in AG#6 (PR #9, stacked on #8); contract grew to four files, hash `8fd789ba65d5` (AG#5, PR #8; CW proof: `flow_extensions_contract_spec.rb`); PR template + labels (AG#7, PR #10). Staging still runs the earlier HTTP tools until PR #9 merges and the pack is applied.
- 2026-10-08 CW: `kanban/conversations/:display_id/deal[/items]` live on staging (image `4.18.0-6ebd0dc7d-ee`), capabilities `deal.items` and `products.read` announced.
- 2026-10-08 AG+CW: the toolpack of AG#6 was applied to the staging agent 2 (`apply-toolpack.ts --apply`, idempotent on the second run); end to end conversation 22: 8 m3 fck 30 + pumping = R$ 4.880,00 from the catalog, the agent never named a card, `actor_kind: agent_bot`. The agent's earlier tools that took a card id are disabled.
- 2026-10-08 AG+CW: both READMEs rewritten for flow-chat / flow-agents (AG branch `docs/readme-flow-agents`, CW commit with this line); the AG README no longer says "nothing is implemented" nor "no image of its own". See B-14 for what was not renamed.
- 2026-10-09 AG+CW: identity on staging: Chatwoot image `4.18.0-a0dcb1877-ee` + `flow:identity:apply` (scheduled task, deleted), agents image `agents-ee:1ecbbed3` (AG PR #14 head, unmerged) through the new env `AGENTS_IMAGE`; both sign-in screens checked in light and dark. Upstream issue fazer-ai/agents#1175: the code-sandbox budget test fails on 1 CPU (rerun the shard when it hits).
- 2026-10-09 AG: own branding editor (AG issue #15, PR #16, stacked on #14): the Free edition's three branding writes implemented by us (fleet-level audit) and Admin > Branding as a real editor instead of the Pro gate. On staging as `agents-ee:4deeb6b7`; an unauthenticated PATCH answers 401; assets persist in the `storage` volume (`/app/storage/branding`).
- 2026-10-09 AG: PRs #14 (Flow identity, `32aa6e7e`) and #16 (own branding editor, `ad3dd787`) merged into `main`; issues #13 and #15 closed. Staging `agents-ee:4deeb6b7` has the same tree as `main`.
- 2026-10-09 AG+CW: contract grew to `deal.quote` (hash `e6a2dfc71b9e`, CW `4b4951170`, AG PR #19 with the tool `get_deal_quote`); AG PR #17 (upstream v1.40.2 merge) and #18 (flow-compat CI) wait for the owner's merge. Branch `claude/jolly-johnson-bq9kim` of CW deleted on the owner's order (tips `ed80879c5`, `20522ff53`).
- 2026-10-09 AG+CW: AG PRs #17-#19 merged (`main` `ad7e8c84`); images published: `agents-ee:ad7e8c84` and `chatwoot:4.18.0-13b993ab8-ee` (`13b993ab8-ee`, `4.18.0-ee`, `latest-ee`; has `deal.quote` and `handled_by_agent`). Staging still runs `chatwoot:4.18.0-a0dcb1877-ee` and `agents-ee:4deeb6b7` until `FLOW_IMAGE_TAG` and `AGENTS_IMAGE` are changed (classifier denied the env writes), then `apply-toolpack.ts --apply` for `get_deal_quote`. Coolify scheduled-task commands are limited to 255 characters (longer answers 500).
