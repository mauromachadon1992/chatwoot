# Kanban roadmap: sprints and phases

Status: **S0 to S8 built** (hardening done; rollout is yours) (2026-10-08; S0.1 publishing and staging
wait for confirmation and a Coolify token). **Phase P (C0 to C6), compatibility with fazer.ai agents:
C0 done, C1 to C6 proposed.** S6 to S8 were built before Phase P, which changes C6 and settles the AI
assistant (see C6 and "Decisions to confirm").

This plan turns the ten recommendations into sprints. It rests on `PRODUCT.md` (who the product is
for), `DESIGN.md` (the design system), `custom/README.md` (what exists) and two design references,
the Impeccable skill and *Designing User Interfaces*. Every claim about the current state comes from
the code or the screens as they are today.

## 1. Principles for every sprint

1. **A sprint ends in something an agent or an administrator can use**, behind an account toggle
   when it changes behaviour, and ships through `build-ee` → `ee-local check` → staging.
2. **The deal outlives the conversation; an agent sees only what their inboxes and teams allow.**
   Every new list, count, notification and webhook is filtered by `Board.visible_to`, and each
   story has a spec that proves an agent without access gets nothing.
3. **Quiet and familiar.** New screens are built from `components-next`; nothing new is invented
   where `DESIGN.md` already has a pattern.
4. **Upstream stays clean.** Code lives in `custom/`; an upstream file gets the smallest hook, and
   the hook is added to the table in `custom/README.md`.
5. **Measure the value.** Each sprint names the number that says it worked (section 6).

## 2. Definition of Done (every story)

**Code**
- Rails specs for models, services and requests, including the visibility case; vitest for helpers
  and store logic. `rubocop`, `eslint` (0 errors) and the husky hook pass without `--no-verify`.
- Migrations are reversible, indexed for the query they serve, and tested on the dev data.
- Strings in `pt_BR`, `en` and `es` together; server texts in `custom/config/locales`.
- `custom/README.md` (what it does, what it deliberately does not) and `DESIGN.md` (if a pattern
  was added) are updated in the same commit.

**Design gate (UI stories)** (the Impeccable cycle, bounded)
1. A compact `shape` brief before code: job, primary action, states, ranges, what stays untouched.
2. Build with `components-next`, the typography utilities and tokens only.
3. `impeccable audit` and `critique` once on the built surface, plus the repo's design-system
   audit script (Sprint 0) and `detect.mjs`: **0 findings**.
4. One batched visual round: light, dark and 390 px wide, with real data and with every state.
5. Fix the whole batch, confirm with at most one more round, stop polishing.

**Design checklist** (from *Designing User Interfaces* and the UI/UX Playbook, as defaults the
design system may override)
- Touch targets ≥ 44 px on mobile and ≥ 32 px on desktop; thumb-reachable primary action on mobile.
- Contrast ≥ 4.5:1; a state is never carried by colour alone (colour + icon + word).
- Forms: visible labels, size to the data, inline validation, one primary action per view.
- Choices: 2 to 4 options are a segmented control, longer lists a `ComboBox`; no more than ~7
  visible choices at once.
- Every screen has its **empty**, **loading** (skeleton, never a spinner in content), **error** and
  **success** states, written in plain words that say what to do next.
- Destructive steps: `ghost ruby` to open, `Dialog type="alert"` to confirm, Cancel left, plain
  "cannot be undone" copy.
- Tables: real `<table>`, numbers right-aligned and `tabular-nums`, a way to read a zero.
- Microcopy: verbs on buttons ("Schedule", not "OK"), no jargon, no dark patterns.
- Dark mode uses the token layers, never a hand-picked colour.

## 3. Phases and sprints at a glance

A sprint is one releasable increment. Each is sized for roughly a week of focused work at the pace
of the previous phases; recalibrate after Sprint 1, and treat the order, not the dates, as the plan.

| Phase | Sprint | Goal | Recommendations |
| --- | --- | --- | --- |
| 0 Foundations | S0 | Guardrails and shared pieces before more screens | (enabler) |
| 1 Daily use | S1 | Fit the phone and the day | #4 mobile toolbar, #1 My tasks |
| 1 Daily use | S2 | Deals that arrive by themselves and do not die | #2 auto-create, #3 stale alert |
| 2 Revenue | S3 | Know what happened to a deal | #7 timeline, card events ledger, #5 data capture |
| 2 Revenue | S4 | Forecast and quote | #5 forecast and lost reasons, #6 send quote |
| 3 Leverage | S5 | Rules that do more | #9 automations |
| P Compatibility | C0 to C4 | The fazer.ai agents' Kanban client works against Flow unchanged | (enabler, see Phase P) |
| 3 Leverage | S6 | Connect and import | #10 webhooks, CSV |
| 3 Leverage | S7 | Assistance with AI | #8 AI summary (starts with a spike) |
| P Compatibility | C5, C6 | Flow-only abilities for the agent; events to the agent | (enabler, see Phase P) |
| 4 Release | S8 | Harden and roll out | (enabler) |

Dependencies: S3's card events ledger feeds S5 (run log), S6 (webhooks) and S7 (summary input).
S2's auto-create needs S0's toggle pattern. S4's forecast needs S3's fields. S7 needs the licence
check below. C0 to C4 need nothing from S6 to S8 (already built); C6 builds on S6's webhook sender.

---

## Phase 0: Foundations

### S0: Guardrails and shared pieces
**Goal:** later sprints reuse instead of rebuild, and drift is caught by a script, not by eye.

| Story | What | Done when |
| --- | --- | --- |
| S0.1 | **Ship the baseline.** Push `feat/kanban`, publish the image, promote on staging (needs a Coolify token), confirm the bell, reminders and tasks run there. | staging runs the current build; rollback tag noted |
| S0.2 | **Design-system audit as a script** (`custom/script/design-audit`): the checks used in the last audit (native elements, literal hex, hand-built type, non-logical spacing, content spinners, icon-only buttons without label and tooltip) plus `detect.mjs`; run by `flow-tools/run.sh`. | exits non-zero on a finding; 0 findings today |
| S0.3 | **Extract the repeated pieces** (`impeccable extract`): `EmptyState` (icon tile, `text-heading-2` title, one sentence, optional action), `SkeletonRows`, a `StatePill` (icon + word + tone) and `SegmentedControl` stays. Replace the hand-built copies in the sections already shipped. | no screen builds its own empty or loading block |
| S0.4 | **Account toggles**: one `flow_kanban_features` object in `account.settings` (auto_create, stale_alerts, forecast, ai_summary, webhooks), read by a `Custom::Kanban::Features` helper and editable by a super admin like the card fields. | each later behaviour has an off switch |
| S0.5 | **Usage counters** (Rails notifications, no PII): deals created by hand and by rule, tasks created and completed late, notifications opened, stale cards, quotes sent. | a dev query prints the counters |

**Risks:** S0.1 depends on a new Coolify token. **Exit:** baseline on staging; audit script green;
no behavioural change for users.

---

## Phase 1: Daily use (the agent)

### S1: Fit the phone and the day (#4, #1)
**Goal:** an agent in the field opens the Kanban on the phone and sees, first, what to do today.

**S1.1 Compact mobile toolbar (#4).** *Evidence:* at 390 px the toolbar stacks four rows (about
215 px) before the first column.
- **Brief:** below `md`, one row: board name, search, a **Filters** button with the active-filter
  count (opens a `Popover`, which is already a centred sheet on mobile), and **New card** as an icon
  button in the thumb zone. Desktop is unchanged.
- **States:** no filters, filters active (count + "Clear"), filter list loading. Targets ≥ 44 px.
- **Accept:** first column starts within ~96 px of the top at 390 px; every filter still reachable
  in two taps; desktop screenshot identical to today.

**S1.2 My tasks (#1).** A third view next to *Board* and *Report*.
- **Brief:** list grouped **Overdue / Today / Upcoming / Done recently**; each row has the checkbox,
  type icon, title, the deal (opens the card panel), due label (word + tone, as in the card panel)
  and assignee. Agents see their own by default; administrators get a `SegmentedControl`
  *Mine / Everyone*. Completing a row is inline and reversible ("Undo" toast). The bell's task
  notifications deep-link to the right row.
- **API:** `GET kanban/my_tasks?scope=mine|all&status=…&page`, filtered by visible boards; counts for
  the tab badge.
- **States:** empty ("Nothing due. Schedule the next step on a deal."), loading skeleton, error
  with retry, a long list (paginate by group, never one endless scroll).
- **Tests:** an agent never sees a task on a board they cannot see; completion updates the card
  badge; the grouping follows the account time zone.
- **Accept:** from the bell to a completed task in three taps on the phone.

**Exit:** both on staging behind no toggle (read-only features). **Metric:** tasks completed late ÷
tasks completed (should fall).

### S2: Deals that arrive by themselves and do not die (#2, #3)
**Goal:** no deal is lost to a forgotten card or a forgotten follow-up.

**S2.1 Auto-create a deal (#2).** *Evidence:* nothing creates a card when a conversation arrives.
- **Rule (board settings → "Automatic deals"):** per board, pick inboxes; a new conversation from
  a contact **without an open deal** creates one on the first open stage, titled by the contact,
  linked to the conversation, assigned to the conversation's assignee when it has one. Off by
  default. Piloted on one board and one inbox.
- **Guards:** never a second open deal for the same contact; a contact with only won or lost deals
  gets a new one; group conversations skipped; a per-board daily cap (a safety valve, shown in the
  settings); the card shows a quiet "Created automatically" tag until an agent edits it.
- **Design:** a section in `BoardSettingsPanel` using `Switch`, a `TagMultiSelectComboBox` for
  inboxes and an `Input type=number` for the cap; the sentence states what will happen in full.
- **Tests:** dedup, cap, inbox filter, visibility of the created card, event ordering (the
  listener runs after the conversation exists), idempotence under a retried job.
- **Accept:** a test conversation creates exactly one card; a second message does not.

**S2.2 Stale alert (#3).** *Evidence:* time in stage already exists on the card.
- **Rule:** per stage, an optional "days without movement" (admin, stage settings); won and lost
  stages excluded. A card past it gets a `StatePill` ("Stalled 6 d", icon + word, amber) and the
  assignee gets **one** `card_stale` notification per stall (re-armed when the card moves).
- **Job:** daily, indexed query on `stage_changed_at`.
- **Design:** the stage row gains a number field with a unit; the board can filter "Stalled" with
  the existing toolbar pattern.
- **Tests:** threshold, re-arm on move, no notification for unassigned or invisible cards.
- **Accept:** a card moved back in time gets exactly one notification and one pill.

**Exit:** S2.1 on for the pilot board only. **Metric:** share of deals created automatically; deals
older than the stage threshold (should fall).

---

## Phase 2: Revenue visibility (the administrator)

### S3: Know what happened to a deal (#7, ledger, #5 capture)
**Goal:** the history of a deal is one list, and the data a forecast needs is being captured.

**S3.1 Card events ledger (enabler).** `flow_kanban_card_events` (card, actor, kind, data,
created_at): written by callbacks for stage moves, value changes, task completed, assignee changed,
deal created (manual or automatic), lost reason set. Append-only; backfilled from `stage_transitions`.
Feeds the timeline now and webhooks and AI later.

**S3.2 Timeline (#7).** A "History" section in the card panel.
- **Brief:** newest first, grouped by day, each entry an icon, a sentence ("Ana moved it to
  Proposal"), and the time; value changes show old → new with `tabular-nums`. Collapsed to the
  last five with "Show all".
- **States:** a card with only its creation event, loading skeleton, long history (paginate).
- **Accept:** every stage move since Phase 2 appears with its actor; an automation move says so.

**S3.3 Capture for forecasting (#5, data only).**
- `expected_close_on` on the card (a date `Input`, optional), `win_probability` on the stage
  (0–100, default by stage type), a **lost reasons** list per account (admin, Settings, same page
  pattern as Products), and `lost_reason_id` on the card.
- **Moving to a lost stage asks for the reason** in a small `Dialog` (a `ComboBox` and an optional
  note); skipping is allowed ("No reason") so the drag never blocks the agent. Dragging back clears it.
- **Tests:** the dialog path and the API path agree; a reason from another account is refused.
- **Accept:** a deal marked lost carries a reason or the explicit "No reason".

**Exit:** ledger and fields live, no new report yet. **Metric:** share of lost deals with a reason.

### S4: Forecast and quote (#5, #6)
**Goal:** the administrator reads next month's revenue; the agent sends a quote in two taps.

**S4.1 Forecast and lost reasons (#5).** Two blocks in *Report*, using the report-strip and funnel
table patterns.
- **Forecast:** open deals by expected-close month, **weighted** (value × stage probability) beside
  the **unweighted** total, per agent on demand; deals without a date in a separate "No date" row
  (never silently dropped).
- **Lost reasons:** counts and value by reason, plus "No reason".
- **States:** nothing in the period, partial data ("12 of 40 open deals have a close date": a
  `StatePill` linking to the filter), loading, error.
- **Tests:** weighting arithmetic in cents, period boundaries in the account zone, visibility.
- **Accept:** the figures match a hand calculation on the demo board.

**S4.2 Send quote (#6).** A "Send quote" action in the card panel's value section.
- **Brief:** composes a message from the product lines (name, quantity, unit price, discount, total)
  and the deal total in the account currency, in a template the admin can edit (Settings → Quote
  message, with a live preview); it **pre-fills the reply box of the linked conversation** and the
  agent reviews and sends. Nothing is sent without the agent.
- **States:** no lines yet ("Add products to build a quote", link to the lines), no conversation
  linked (offers to link one), several conversations (pick the channel), long list (WhatsApp length
  warning with a split).
- **Tests:** formatting (currency, decimals, pt_BR), the agent without access to the conversation
  cannot compose into it, the sent quote is logged to the ledger.
- **Accept:** a deal with three lines produces the message in one tap and appears in the composer.
- **Later, not now:** PDF.

**Exit:** both behind the `forecast` toggle (S4.1) and none (S4.2). **Metric:** quotes sent per
won deal; open deals with a close date.

---

## Phase P: Compatibility with fazer.ai agents (C0 to C6)

**Why.** fazer.ai agents (the `flow-agents` fork, `custom/ROADMAP.md` there) drives the Kanban of
the fazer.ai Chatwoot Pro: `/kanban/boards`, `/boards/:id/steps`, `/kanban/tasks`, and a
`kanban_task` object embedded in the conversation. Flow's Kanban has the same prefix and different
resources. Left alone, the agent's funnel tools break, and `GET /kanban/tasks` is worse than broken:
it exists in both and answers with "My tasks" (S1.2), a different type, instead of failing.

**Decision.** The agents' fork stays identical to upstream (zero diff in `src/` and `tests/`), so
upstream merges are routine and the agent's own Kanban improvements arrive for free. **Flow speaks
the Pro dialect** in a compatibility layer inside `custom/`; what Flow has beyond Pro (lost reasons,
card tasks, items, history, forecast, quote) is reached by the agent as declarative HTTP tools and,
later, an MCP server, never as code in the fork. "100% compatible" means the whole surface the
agents' client uses (15 operations plus the embedded `kanban_task`), proven by the agents' own tests
and a harness that runs the agents' real `ChatwootClient` against this app. It does not claim
compatibility with the Pro UI or with clients not seen here.

**The contract** lives in `custom/contracts/pro-kanban.md` and `pro-kanban.v1.schema.json`, the same
copy as in `flow-agents`, with a hash test on each side so neither changes alone. The 15 operations
and the card shape are in the agents' roadmap, Annexes A and B.

### Principles for this phase (on top of section 1)

1. **Superset, never subset.** The compatibility layer accepts and returns the union of Pro's and
   Flow's fields. A field the agents require is never missing (it is `null` or `[]`).
2. **Flow stays the model.** Controllers named `Compat::`, serializers in Pro's shape over
   `Custom::Kanban::Card` and `Stage`; no second data model. Money stays in integer cents; the
   numeric `value` exists only in the Pro serializer.
3. **No leak.** `kanban_task` goes into the authenticated conversation API and the Agent Bot webhook,
   never into the push payload clients and the widget receive (the presenter already records that
   this leaked once). A spec proves it.
4. **The agent is a named actor.** What it writes shows in the deal's history as the agent, not as
   the administrator who owns the token.

### C0: Contract and harness
**Goal:** a failing, readable list of what is missing, before any code.
- Write the contract and schema from the agents' client and fixtures; copy it to `flow-agents`.
- Request specs generated from the fixtures (one per operation), all pending.
- `custom/harness/` script that runs the agents' real `ChatwootClient` through the full cycle
  (create board and steps, create a card, link a conversation, read the context, move, edit, label,
  set attributes, reset, read without permission) against `ee-local` and prints field-level diffs.
- **Accept:** the harness runs and lists 15 failures; a changed contract line fails the hash test.

**Status (2026-10-08).** Contract, schema and hash are in `custom/contracts/` (the same copy as in
`flow-agents-ee`; both repositories compute `a73828044463…`). The harness and a reference
implementation live in `flow-agents-ee` (`custom/harness/`): it passes 16/16 against the reference and
3/16 against a server that does not speak the dialect. Here, `spec/custom/kanban/pro_contract_spec.rb`
checks the hash and lists the 15 operations, each skipped by name with the sprint that delivers it.
Still open: running the harness against this app in `ee-local` (needs C1) and turning each skipped
example into a request spec as its sprint lands.

### C1: Pro routes and the `/kanban/tasks` conflict
**Goal:** operations 1 to 5 and 8 to 11 answer in Pro's shape (6 and 7 belong to C4).
- **Rename first, in the same commit:** the "My tasks" list moves to `GET /kanban/my_tasks`; the
  store (`flowKanban.js`, `api/flowKanban.js`) and the S1.2 specs move with it. It had
  already reached the staging image (S1.2), so it moved in one image with its frontend.
- `GET /kanban/tasks[?board_id=]` returns cards in Pro's shape; `GET /kanban/tasks/:id` returns the
  bare card (labels as an array of strings); `POST /kanban/tasks` creates, deriving the contact from
  the conversation and the first open stage when no step is given.
- `GET/POST /kanban/boards/:id/steps` as `{steps: […]}`; `cancelled` is `stage_type == lost`.
  `POST /kanban/tasks/:id/move` takes `board_step_id` and `insert_before_task_id` and delegates to
  `Card#move_to!`; a move onto a lost stage still accepts `lost_reason_id` and `lost_note`.
  `PUT /kanban/boards/:id` and `POST /kanban/boards` accept the `{board: {…}}` root key.
- **Tests:** visibility (an agent without the board gets 404, never a different type), the old
  `/tasks` meaning gone, root keys, a card created from a conversation links it by `display_id`
  (with an internal id different from the display id, as the Conversation ids rule demands).
- **Accept:** operations 1 to 5 and 8 to 11 pass in the harness.

**Built (2026-10-07), measured with the agents' harness against a running stack: 1/16 before, 10/16 now.**
Operations 1 to 5 and 8 to 11 pass (C1), and the conversation's `kanban_task` (operation 15, the read
half of C3). Also done: the rename to `/kanban/my_tasks`, the `X-Flow-Kanban-Dialect` header and
`capabilities` in the settings (from C5, early), the stage `description`, the agents' service user and
`HumanAdministrator` (the security finding of the review: an administrator token in the agents' hands
must not reach webhooks, imports or automations), and `.gitattributes` for the contract. A board made
with the `{board:}` root key gets no default stages (the caller defines its own); this is a decision to
confirm against a real Pro board. See README, "Phase P".

**C2 and C4 built (2026-10-07): the harness passes 16/16** on the dev stack, with the agents' own tests
(78) green. Done: deal priority, dates, labels and custom attributes (UI: details section and priority
pill), board agents and `update_inboxes`/`update_agents`, history actors, the 30-runs-per-deal-per-hour
cap, and `kanban_task` in outgoing `webhook_data`. To do: rebuild the image and re-run the harness on
ee-local, merge `chore/contracts-lf` in flow-agents-ee (its `main` stores the contract with CRLF, so the
byte hash differs; the content is identical after LF normalisation).

### C2: Pro fields on the card (a UI story)
**Goal:** operations 12 to 14, and the fields the agent reads and writes.
- **Columns:** `priority` (`urgent|high|medium|low`), `start_at`, `due_at` (start before due),
  `custom_attributes` (jsonb), card labels (the account's `Label` table, same mechanism as
  conversations and contacts; `PATCH` replaces the whole set), and `description` on the stage
  (at most 120 characters). Reversible migrations, indexed for the filters that use them.
- **Serializer:** `status` derived from the stage type; `value = value_cents / 100.0` out, integer
  cents in. The existing "card fields" are the definition of the attributes (confirm in C0).
- **Design:** priority, dates, labels and attributes in the card panel with the existing patterns
  (`components-next`, `StatePill` for priority, `ComboBox` for labels), with every state, light and
  dark and 390 px, then the design gate. Strings in pt_BR, en and es.
- **Tests:** `null` clears description and dates; labels replace, not append; attributes merge in
  the caller as the agents do; priority and date validation return 422 in the account's language.
- **Accept:** operations 12 to 14 pass; a human edits the same fields in the panel.

### C3: The conversation carries its card
**Goal:** operation 15 and the attribute mirror.
- `GET /conversations/:display_id` includes `kanban_task`, the same shape as the card show.
- **One card per conversation, by rule:** exactly one open linked card is that card; several open
  ones, the most recently updated; only won or lost ones, `null`. The Flow UI keeps showing all.
  The rule and its limit are written in `custom/README.md`.
- Add `kanban_task` to the Agent Bot webhook payload only. **Verify first** where the conversation
  presenter is shared with the widget and push, and keep the new key out of those paths.
- **Tests:** a leak spec for the widget and push payloads; the single, several and none cases; an
  internal id different from the display id.
- **Accept:** the agents' context loader (`loadKanbanContext`) builds the funnel from one GET.

### C4: Board agents, the actor and rule chaining
**Goal:** operations 6 and 7, and an honest history.
- `POST /boards/:id/update_inboxes` and `update_agents` (idempotent diffs). Agents become a board
  restriction next to teams and inboxes, in a new `flow_kanban_board_agents` table, and
  `Board.visible_to` honours it without narrowing today's team rule.
- **Actor.** `card_events` gets `actor_kind` (`user`, `rule`, `agent_bot`) and `actor_name`, and the
  history shows "Agent X moved it". The agent is a **service user** whose token the agents use,
  flagged `agent_bot` in its record; nothing is sent from the agents' side. `by_rule`, today
  inferred from `Current.user.nil?`, becomes `actor_kind == rule`.
- **Chaining.** Rules (S5) fire on conversation labels and status; an agent that labels or resolves a
  conversation now triggers them, which is wanted. The run-once-per-episode guard stops the same
  rule acting twice on a deal, not rule A adding the label that fires rule B. Add a depth limit per
  request and a spec with two rules that would loop.
- **Tests:** an agent not in a restricted board gets nothing; the actor on every write the agents
  make; the loop is cut and the run log says why.
- **Accept:** operations 6 and 7 pass; the deal's history names the agent.

### C5: Flow-only abilities exposed to the agent
**Goal:** the agent uses what Pro does not have, with no code in its fork.
- Keep stable, documented (OpenAPI) and versioned: `lost_reasons`, `PATCH cards/:id/move` with a
  reason, `cards/:id/tasks`, `cards/:id/items` and the product catalogue, `PATCH cards/:id` with
  `expected_close_on`, and `cards/:id/events`.
- **`GET /kanban/cards/:id/quote_preview`** (new): the quote text and the totals computed on the
  server, in the account's currency and locale. Today the text is built in the dashboard
  (`quote.js`) and `POST cards/:id/quote` only records "quote prepared", so an agent could not reuse
  it and would have to calculate. The dashboard moves to the same endpoint, so there is one place.
- `GET /kanban/settings` also returns `api_version` and `capabilities`, so a client can tell which
  of these exist. An MCP server over the same operations is optional.
- **Tests:** only the account's own lost reasons and products; totals in cents match the dashboard;
  an agent without access to the conversation cannot prepare a quote for it.
- **Accept:** a test agent configured with HTTP tools marks a deal lost with a reason, schedules a
  task, adds a product line and reads the quote, each as the `agent_bot` actor.

### C6: Events to the agent (builds on S6; design open)
**Goal:** Flow tells the agent about a deal without custom code in the agents' fork.

**What S6 shipped, and why it does not fit the agents' receptor as is.**
- S6 webhooks (`flow_kanban_webhooks`) send `{event, occurred_at, account_id, deal, data}` for
  `deal.created|moved|won|lost|value_changed` and `task.created`, signed `X-Flow-Signature:
  t=<timestamp>,v1=<hex>` (HMAC-SHA256 over `"<timestamp>.<body>"`).
- The agents' generic receptor expects `{event_id, conversation_ref, text}` with HMAC-SHA256 over the
  raw body in `x-webhook-signature`, and speaks into that conversation. The shapes, the signature and
  the purpose differ, and an S6 payload carries no conversation.
- S6 also refuses targets that are not public HTTPS (loopback, private ranges, link-local). The
  agents' container on the same Docker network is therefore **not a valid S6 webhook target**; it
  would need a public HTTPS address.

**Design to decide before building.** `conversation_ref` is minted by the agents the first time one
of its HTTP tools runs in a conversation, so Flow cannot compute it. Two ways to give Flow a
reference without code in the agents' fork:
1. A Flow HTTP tool the agent calls once per conversation, passing `{{conversation_ref}}` and the
   display id; Flow stores it on the card's conversation link. Then a rule action `nudge_agent` posts
   `{event_id, conversation_ref, text}` signed the agents' way, through its own narrow sender
   (`FLOW_AGENTS_BASE_URL` as an explicit allowlist entry, so S6's strict guard stays strict).
   `event_id` is the rule's episode key, so a retry acts once.
2. Do not nudge from Flow at all: the agents already re-engage on their own follow-ups (24 h window
   aware); use Flow rules only to create tasks for humans.

Recommendation: **option 2 first** (nothing to build, no new surface); option 1 only if a pilot shows
stalled deals the agent's own follow-ups miss.
- **Tests (option 1):** retried event handled once; an invisible board never leaks; no nudge outside
  the WhatsApp 24 h window (the agents' own rule), logged as skipped.
- **Accept (option 1):** a stalled deal with a registered conversation produces one agent message.

**Metrics (phase P):** operations passing in the harness (0 to 15); field-level differences (zero);
agent actions in the deal history with the correct actor (all).

**Risks.** The fazer.ai Pro dialect changes upstream: the agents' fork runs a daily merge preview
plus the harness, and a red run names the difference before any merge. The contract is inferred from
the agents' open client, not from the Pro source, so creation bodies, list envelopes and the
meaning of `status` are measured by the harness, not assumed.

---

## Phase 3: Leverage and integration

### S5: Rules that do more (#9)
**Goal:** the board runs the routine follow-ups.

- **Triggers added:** *No reply for N hours* (customer or agent side, chosen), *Deal created*,
  *Stalled*. **Actions added:** create a task (title, type, due in N hours/days, assignee: deal's
  agent or a fixed agent), assign an agent, add a label to the conversation, besides move.
- **Model:** a rule has one trigger and an ordered list of actions; a deal runs each rule at most once
  per trigger episode (no loops: card moves never trigger rules, as today).
- **Design:** the Automations section becomes a rule list with an inline editor (the board settings
  are already a side panel, so no second one opens): sentence summary in the list, `Switch`, delete with
  a confirm. A **run log** ("Recent runs": what ran, on which deal, when, with a link) from the
  ledger answers "why did it move?".
- **States:** no rules (offers three starter templates), a rule whose stage or agent was deleted
  (flagged "Needs attention", disabled, never silently running), a long log.
- **Tests:** per-trigger episode idempotence, deleted targets, visibility of created tasks and
  notifications, the daily cap.
- **Accept:** "Moved to Proposal → task 'Follow up' in 2 days" creates one task per deal.

**Built:** see README, "Sprint 5". Rules flagged "Needs attention" are skipped, not disabled,
so fixing the target brings them back.

**Metric:** tasks created by rules; follow-ups completed on time.

### S6: Connect and import (#10)
**Goal:** the rest of the ecosystem hears about deals, and data comes in without retyping.

**S6.1 Webhooks.** Deal created, moved, won, lost, value changed, task created, from the ledger.
Signed payloads, retries with backoff, per-account endpoints managed by an administrator with a
delivery log and a "Send test" button. **Sign them as the fazer.ai agents' receptor expects**
(HMAC-SHA256 of the raw body in `x-webhook-signature`, `event_id` as the idempotency key; see C6),
so connecting the agent costs no code.
- **Decision:** reuse Chatwoot's `Webhook` (needs a hook on `ALLOWED_WEBHOOK_EVENTS`, an upstream
  constant) or own table `flow_kanban_webhooks` (no upstream touch). **Recommendation:** own table.
- **Design:** Settings page with the table pattern (URL, events, last delivery with word + icon
  status), create/edit in a `Dialog`, secret shown once.
- **Tests:** signature, retries, only the account's own events, no deal from an invisible board
  leaks (webhooks are account-level: documented and admin-only).

**S6.2 CSV import and export.** Products and deals.
- **Import:** upload, a **preview of the first rows with the mapping**, a **dry run** that reports
  every error by line before anything is written, then the import as a background job with progress
  and a downloadable error file. Limits stated up front (rows, size).
- **Export:** the current board filters, visible boards only, UTF-8 with BOM for spreadsheets,
  money as decimals in the account currency.
- **States:** wrong file, missing columns, partial failure, huge file.
- **Tests:** dedup keys (SKU, contact e-mail or phone), idempotent re-import, a formula-injection
  guard on export (`=`, `+`, `-`, `@` prefixes).

**Built:** see README, "Sprint 6". Decision 5 went with the recommendation (own table).

**Metric:** deals/products imported; webhook deliveries succeeded ÷ attempted.

### S7: Assistance with AI (#8)
**Goal:** a summary and a suggested next step on a deal, on the agent's request.

- **Spike first (≤ 2 days):** which assistant (Captain, fazer.ai Agents), whether this installation's
  plan includes it (the ee-local reports `community`), cost per call, what data leaves the
  installation, and the reusable services (`Captain::Llm::ContactNotesService` is the nearest
  pattern). **Go/no-go at the end of the spike.**
- **Feature (if go):** a **Summarize** button in the card panel that drafts a deal summary from the
  linked conversations and the card history, and **suggests one next task**; both appear as a
  **draft the agent accepts, edits or discards**. Labelled "Generated by AI", never written
  automatically, rate-limited per agent, off by default per account (`ai_summary` toggle).
- **States:** nothing to summarize, generating (skeleton), failure (plain message, retry), content
  too long (says what was used).
- **Tests:** only conversations the agent can access are sent; the toggle; the draft is not saved
  until accepted; failures leave the card unchanged.
- **Accept:** a deal with two conversations produces a draft in the agent's language.

**Spike result (go).** Assistant: **Captain**, through `Captain::BaseTaskService` (the same base
as its own conversation summary); nothing from fazer.ai Agents is called from inside the app. Plan:
this installation is Enterprise (`INSTALLATION_PRICING_PLAN=enterprise`, `captain_tasks` on, 100,000
responses available), not the community plan the ee-local once reported. Credentials: no
`CAPTAIN_OPEN_AI_API_KEY` is set in dev, so the live call could not be tried: tests replace the AI
call, and a super admin must add the key (Settings → Captain) before the first real summary.
Cost: one call is at most about 30,000 characters in (about 8,000 tokens) and 300 tokens out with
the default `gpt-4.1-mini`, a fraction of a cent, and 10 an hour per agent caps it. Data: see README,
"Sprint 7". **Built:** see README, "Sprint 7".

**Metric:** drafts accepted ÷ generated.

---

## Phase 4: Release

### S8: Harden and roll out
- **Whole-product audit:** the design audit script, `impeccable audit` and `critique` on every new
  surface, a keyboard-only pass and a screen-reader pass of the bell, My tasks and the editors.
- **Performance:** N+1 review on boards with 10,000 cards, index review for the new queries, the
  cost of the daily and per-minute jobs.
- **Security review** (`security-review`): visibility on every new endpoint and export, webhook
  signing, import limits.
- **Rollout:** features on per account, pilot board first, one retrospective; docs and `PRODUCT.md`
  refreshed; the roadmap closed or re-planned.

**Built:** the audit, the performance review and the security review (README, "Sprint 8"); `PRODUCT.md`
and the README refreshed. **Left for the rollout, in this order** (none needs code):
1. Build the image (`build-ee`), check it in `ee-local`, publish it (`publish-ghcr`) and promote it on
   Coolify staging (needs a valid Coolify token).
2. In Super Admin, turn on per account what the pilot needs: *Automatic deals* (and pick the pilot board
   and inbox in the board settings), leave *AI deal summary* off until a Captain API key is set.
3. Pilot with one board for two weeks, then read the metrics of section 6 with
   `rake "flow:kanban:metrics[ACCOUNT_ID,DAYS]"`, and note what surprised.
4. Re-plan from the retrospective. Candidates already named: stale-alert preferences per agent, quote as
   PDF, an `hmac` verification snippet for webhook receivers, a Kanban export limit for agents if the
   pilot asks for one, running the image as a non-root user, and clearing the Trivy findings that
   only an upstream sync fixes.

---

## 4. Per-sprint ritual

1. **Plan:** confirm the sprint's brief (the *shape* round), the toggles and the metric.
2. **Build:** one story at a time, specs first for the visibility case.
3. **Verify:** Definition of Done and the design gate.
4. **Ship:** `build-ee`, `ee-local check`, staging, pilot.
5. **Review:** read the metric, note surprises, adjust the next sprint.

## 5. Risks

| Risk | Where | Mitigation |
| --- | --- | --- |
| Automation noise (duplicates, wrong deals) | S2.1, S5 | opt-in per board, dedup, daily cap, visible "created automatically", run log |
| Notification fatigue | S2.2, S5 | one per stall or episode, per-agent preferences considered in S8 |
| Upstream merges (every 1 to 3 days) | all | `custom/` only, hooks listed, `schema.rb` rule in the README |
| AI licence, cost or privacy | S7 | spike with a go/no-go, off by default, accessible conversations only |
| Large boards slow the new lists | S1, S4, S8 | indexes designed with each query, 10,000-card test in S8 |
| Data quality hurts the forecast | S3, S4 | "No date" and "No reason" shown, never hidden; completeness `StatePill` |
| `GET /kanban/tasks` means two things (My tasks vs Pro cards) | C1 | rename to `/my_tasks` in the same commit, before anything is published |
| History names the administrator, not the agent | C4 | `actor_kind` plus a service user flagged `agent_bot` |
| The agent's labels and status changes chain rules | C4 | depth limit per request, spec with two looping rules |
| `kanban_task` leaks into a public payload | C3 | only the authenticated conversation API and the bot webhook; leak spec |
| Pro dialect drifts upstream | P | contract hash test, harness, daily merge preview on the agents' fork |

## 6. How we will know it worked

| Sprint | Number | Direction |
| --- | --- | --- |
| S1 | tasks completed late ÷ completed | down |
| S2 | deals created automatically ÷ all; deals past the stage threshold | up; down |
| S3 | lost deals with a reason | up |
| S4 | open deals with a close date; quotes sent per won deal | up |
| S5 | follow-ups completed on time | up |
| S6 | deals/products imported; webhook success rate | up |
| S7 | drafts accepted ÷ generated | up |
| C0 to C4 | operations passing in the compatibility harness | 0 to 15 |

## 7. Decisions to confirm

1. **Cadence:** is "one releasable increment per sprint, about a week" the right size for you?
2. **Pilot:** which board and which inbox pilot the automatic deals (S2.1)?
3. **Order:** keep Phase 2 (revenue) before Phase 3 (leverage), or bring #9 automations forward?
4. ~~**AI assistant:** Captain or fazer.ai Agents for S7?~~ **Settled by S7: Captain** (`Custom::Kanban::DealSummaryService` builds on `Captain::BaseTaskService`). The fazer.ai agents are not the engine of the summary.
5. **Webhooks:** own table (recommended) or Chatwoot's `Webhook` with an upstream hook?
6. **Quote:** text into the composer now and PDF later, as planned?
7. **Roles:** lost reasons, probabilities, stale thresholds and rules are administrator-only; agree?
8. **Compatibility:** may the card gain priority, dates, labels and custom attributes (C2) so the
   fazer.ai agents work unchanged, next to card tasks, which already cover scheduling?
9. **Agent identity:** a dedicated service user flagged `agent_bot` (recommended), or an
   administrator's own token?
10. **Cards per conversation:** is "the most recently updated open card" the right rule for the one
    card the agent sees (C3)?
11. **Board agents:** is a per-agent board restriction (C4) wanted, or should `update_agents` be
    accepted and ignored?
12. **Nudging the agent from Flow (C6):** option 2 (no nudge; the agents' own follow-ups plus human
    tasks) or option 1 (store `conversation_ref`, add the `nudge_agent` action)?
