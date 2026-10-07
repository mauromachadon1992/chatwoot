# Flow customizations

Everything the Flow fork adds on top of `fazer-ai/chatwoot` lives here, so merges from
upstream rarely touch it.

## How it plugs in

- `lib/flow_custom/engine.rb` is a Rails engine required from `config/application.rb`. It
  autoloads `custom/app`, registers `custom/db/migrate`, loads `custom/config/locales` and
  prepends our routes (`lib/flow_custom/routes.rb`).
- Chatwoot treats `custom` as an extension next to `enterprise` (`ChatwootApp.extensions`),
  so every `prepend_mod_with('Foo')` / `include_mod_with('Foo')` in upstream code picks up a
  `Custom::Foo` module from here. That is how we hook in without editing upstream classes:
  - `Custom::AsyncDispatcher` adds our listeners.
  - `Custom::Concerns::Account` adds account accessors.
  - `Custom::Internal::CheckNewVersionsJob` restores the Chatwoot Hub plan sync (see below).

## Chatwoot Enterprise

`enterprise/` ships with the fork and loads before `custom/` (`ChatwootApp.extensions` is
`%w[enterprise custom]`), so a `Custom::` module wraps the `Enterprise::` one for the same
class. `DISABLE_ENTERPRISE=true` turns it off; we run with it on, and every spec under
`spec/custom` and `spec/enterprise` passes with both loaded.

The Enterprise features (SSO/SAML, Captain, audit logs, custom roles, SLA and the rest of
`enterprise/config/premium_features.yml`) need a **Chatwoot Inc** license in production. A
fazer.ai license covers fazer.ai's Pro code, not these (fazer.ai's README says so). The
license is not code: Chatwoot Inc ties it to the installation's `INSTALLATION_IDENTIFIER`,
and a daily job asks the Chatwoot Hub for the plan and stores it (`INSTALLATION_PRICING_PLAN`,
`_QUANTITY`). Without a plan the installation is `community`, and that job switches premium
features off on every account and resets the premium installation config each day.

- fazer.ai removed that Hub call (fazer-ai/chatwoot #105). `Custom::Internal::CheckNewVersionsJob`
  puts it back with `CHATWOOT_HUB_SYNC=true`, in production with Enterprise on. It is opt-in
  because the call sends the identifier, version, host and, unless `DISABLE_TELEMETRY=true`,
  usage counts; off, the job behaves exactly as fazer.ai's.
- To license production: open Super Admin → Settings on the production installation (its
  identifier, not dev's), follow the subscription link to the Chatwoot Hub, attach the
  license, and set `CHATWOOT_HUB_SYNC=true`. The next daily run stores the plan;
  `Internal::CheckNewVersionsJob.perform_now` in a Rails console does it at once.
- Development and test may use everything without a subscription (`enterprise/LICENSE`):
  `rake flow:enterprise:dev_enable` (optional `SEATS=`) sets the enterprise plan and turns on
  every feature flag except the `chatwoot_internal` and `deprecated` ones;
  `rake flow:enterprise:dev_disable` shows what an unlicensed installation gets. Both refuse
  to run outside development and test (`Custom::EnterpriseDev`).

## Image and deployment

The production image is this fork with `enterprise/` and `custom/`, published privately as
`ghcr.io/mauromachadon1992/chatwoot`. Building, local checks, publishing and the Coolify
stack: `custom/docker/README.md`.

## Upstream files we touch (check these on every merge)

| File | Why |
| --- | --- |
| `config/application.rb` | requires the engine |
| `lib/chatwoot_app.rb` | `extensions` keeps `enterprise` out when it is disabled or removed |
| `app/dashboards/account_dashboard.rb` | super admin fields: Kanban card fields, Kanban features, white label status |
| `lib/brand.rb` | `prepend_mod_with('Brand')`: white label wins in email and the CSAT page |
| `app/controllers/dashboard_controller.rb` | `prepend_mod_with`: brand on the account's own domain |
| `tailwind.config.js` | scans `custom/app/views` |
| `app/javascript/dashboard/helper/actionCable.js` | spreads the Kanban cable events |
| `app/javascript/dashboard/routes/dashboard/kanban/kanban.routes.js` | points the Kanban route at our page |
| `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` | Kanban panel in the conversation sidebar |
| `app/javascript/dashboard/composables/useUISettings.js` | default position of that panel |
| `app/javascript/dashboard/routes/dashboard/Dashboard.vue` | `useWhiteLabel()`: brand after login |
| `app/javascript/dashboard/routes/dashboard/settings/account/components/EmailBranding.vue` | notice when a white label manages the brand |
| `db/schema.rb` | our `flow_kanban_*` tables, white label domain index |
| `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` | one line: `json.partial! 'custom/…'` (the conversation's `kanban_task`) |
| `theme/colors.js` | `n-brand` reads `--blue-9` (fallback `#2781F6`), so the white label re-colours it |
| `app/views/layouts/vueapp.html.erb` | inlines the accent ramps: the login page's (installation) and the white label's (account) |
| `.husky/pre-commit` | `xargs -r`, so a commit without Ruby files does not run rubocop on the whole repo |
| `app/views/super_admin/application/_navigation.html.erb` | renders `_flow_navigation` (the Login page entry) |
| `app/javascript/v3/views/login/Index.vue` | `FlowAuthShell` as the frame; hide options on signup, SSO and Google |
| `app/javascript/v3/views/login/Saml.vue` | `FlowAuthShell` as the frame |
| `app/javascript/v3/views/auth/reset/password/Index.vue` | `FlowAuthShell variant="plain"` as the frame |
| `app/javascript/v3/views/auth/password/Edit.vue` | `FlowAuthShell variant="plain"` as the frame |
| `app/javascript/v3/views/auth/signup/Index.vue` | `FlowAuthShell variant="bare"`; its own photo only without a login page |
| `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` | Settings → Products route (Kanban catalog) |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | Settings → Products entry (administrators, through the route permissions) |

On a `db/schema.rb` conflict, take upstream's version, then run `rails db:migrate` to dump
it again with our tables (and keep the larger schema version).

## Design system

`DESIGN.md` (repo root) documents the Chatwoot dashboard design system as this fork uses it:
tokens, the typography utilities, `components-next` usage and the do's and don'ts. Every new
screen follows it. `.impeccable/design.json` carries the extensions (dark values, shadows,
motion, component snippets) for design tooling. Both files exist only in this fork, so
merges from upstream never touch them.

## Login page

Super Admin → Login page (`/super_admin/login_page`, `FlowAdmin::LoginPagesController`)
gives the whole installation its own sign-in screens: login, SSO, forgot and reset password,
signup and the MFA step. One row in `flow_login_pages` (`Custom::LoginPage`) plus four images
(logo, dark logo, icon, background), served by `LoginPageImagesController` on the same terms as
the white label's. Stored there, not in `installation_configs`, because the Enterprise plan
reconciliation resets `INSTALLATION_NAME`, `LOGO` and `BRAND_COLOR` daily on a `community`
installation.

- What it sets: identity (name, logos, icon, accent colour, for the whole installation,
  dashboard included); copy per language (`pt_BR`, `en`, `es`: title, subtitle, panel
  message; an empty field keeps Chatwoot's text); layout (`background`: one solid card over a
  brand aurora, gradient or image, optionally drifting or slowly zooming; `split`: the form on
  the left and the visual with its message on the right from `lg` up); hiding signup, SSO and
  Google (hiding never shows something that is not configured); support, terms and privacy
  links under the form.
- Precedence (`Custom::DashboardController`): an account white label on its own domain, then
  the login page, then Chatwoot. The installation's ramp is `<style id="flow-installation-theme">`,
  so an account's ramp applied after login sits on top and leaves it in place.
- Frontend: `app/javascript/v3/flow/FlowAuthShell.vue` reads `window.globalConfig.FLOW_LOGIN_PAGE`.
  Without it, it renders Chatwoot's own wrappers byte for byte, so nothing configured means
  nothing changed. With it, the screen's content goes into one surface (the screens' own cards
  become plain sections of it), and no text sits on the background except the panel message,
  which has its own scrim: any uploaded image keeps the copy readable. Animations stop under
  `prefers-reduced-motion`.
- The form previews everything live (light and dark, desktop and mobile), asking the server
  for the accent ramp (`palette` action) so the preview shows the contrast-adjusted tone.

## White label

A super admin brands an account at Super Admin → Accounts → (account) → Configure white
label (`/super_admin/accounts/:id/white_label`). Values live in `accounts.settings`
(`white_label_*`) plus four attachments (logo, dark logo, icon, email logo).

- Dashboard after login, on any domain: `useWhiteLabel()` fetches
  `/api/v1/accounts/:id/white_label` and re-brands the global config, tab title, favicon,
  theme colour and accent ramp.
- The account's own domain: `Custom::DashboardController` renders the login page, title and
  favicon with the brand. Point a CNAME at the installation host and issue its certificate.
- Email, CSAT page and widget: `Custom::Brand` and `Custom::WidgetsController`. The custom
  "Powered by" name and link fall back to the brand name.
- The controller is `FlowAdmin::WhiteLabelsController`, not `SuperAdmin::`, because
  Administrate builds the super admin sidebar from every `super_admin/*` controller. Its
  `palette` action feeds the form's live preview from the same palette code.
- Colour: `Custom::WhiteLabel::Palette` re-hues Chatwoot's 12-step blue (`--blue-1..12`, light
  and dark, plus `--solid-blue*` and `--border-blue*`) in OKLCH, keeping each step's lightness,
  and guarantees contrast: white text on step 9 at 4.5:1 (the brand is darkened if needed, and
  the form says so), step 11 at 4.5:1 and step 12 at 7:1 on the step-3 wash, step 9 at 3:1 on
  the dark page. The layout inlines the stylesheet on the account's domain and
  `useWhiteLabel()` injects it after login. `n-brand` reads `--blue-9`, so every `bg-n-brand`,
  `text-n-blue-11` and `outline-n-brand` follows. Email keeps the raw brand colour (the mail
  layout already picks a readable text colour for it).
- Images are served by `WhiteLabelImagesController` at `/flow/brand/:account_id/:name/:blob_id`,
  not by Active Storage, which sends SVG as `application/octet-stream`, so browsers refuse to
  draw it. The response whitelists the type, sends `nosniff` and a sandboxing CSP, and is
  cached for a year (the URL changes with each upload).
- Signing out of the dashboard also signs the super admin out (`sign_out_all_scopes`). A form
  left open then posts a stale token, and the controller sends the admin back with a message.

## Kanban

What comes next, in sprints and phases with their design gate: [ROADMAP.md](ROADMAP.md).

- Backend: `app/models/custom/kanban/*`, `app/controllers/api/v1/accounts/kanban/*`,
  `app/policies/custom/kanban/*`. Tables are prefixed `flow_kanban_`.
- Frontend: `app/javascript/dashboard/routes/dashboard/flowKanban/`,
  `stores/flowKanban.js`, `api/flowKanban.js`, strings in
  `i18n/fazer-ai/locale/{en,pt_BR,es}/flowKanban.json`.
- A card is a deal of a contact. It links to conversations of any inbox, whatever the
  channel. Board visibility follows inbox and team membership; administrators see every
  board.
- Which fields a card shows is picked per account by a super admin (Super Admin → Accounts
  → Edit → Kanban card fields), stored in `accounts.settings.flow_kanban_card_fields`.
- Specs: `spec/custom/`, `spec/factories/flow_kanban.rb`,
  `app/javascript/dashboard/stores/specs/flowKanban.spec.js`,
  `app/javascript/dashboard/routes/dashboard/flowKanban/specs/`.

### Values, products and the funnel report (phase 2)

- Money is integer minor units (`*_cents`, bigint) everywhere, API included; the dashboard
  formats it (`flowKanban/money.js`). One currency per account,
  `accounts.settings.flow_kanban_currency` (`Custom::Kanban::Currency`, BRL by default, two
  decimal currencies only), changed by administrators in Settings → Products.
- A deal's value (`flow_kanban_cards.value_cents`) is typed while it has no products and is
  the sum of its lines once it has some: `Custom::Kanban::CardItemsService` changes the lines
  and recalculates in one transaction, and the card refuses a typed value while lines exist.
  Removing the last line keeps the last sum, which the agent may then change.
- The catalog (`flow_kanban_products`) belongs to the account: everyone searches it, only
  administrators change it. A line (`flow_kanban_card_items`) copies the product's name, code,
  unit and price when added, so catalog changes, deactivation or deletion never rewrite a deal.
- Stage history (`flow_kanban_stage_transitions`): one row per entry into a stage, written by
  the card's callbacks and, for a deleted stage's cards, by `StageTransition.record_bulk!`.
  Phase 1 cards were backfilled with a single entry into their stage at that time.
- Report (`Custom::Kanban::FunnelReport`, `GET kanban/boards/:id/report?since&until&assignee_id`):
  open now; won and lost in the period (by current stage and when the card got there); win
  rate, average won deal, sales cycle; per stage, what it holds now, the average stay for stays
  that ended in the period, and the funnel of the deals created in the period (reached the
  stage or a later one, a won deal passing every open stage; conversion against the previous
  step). The dashboard shows it under Kanban → Report.
- The board gets `value_cents` and `items_count` per card and `total_value_cents` per stage;
  the lines go only with the card detail (`GET kanban/cards/:id`) and the item endpoints.

### Tasks and stage automations (phase 3)

- **Tasks** (`flow_kanban_card_tasks`, `kanban/cards/:id/tasks`): a title, a type (call,
  meeting, e-mail, follow-up, other), a due date and the agent it is assigned to (the creator
  by default; it must belong to the account). Whoever may work the card may schedule and
  complete its tasks, the way they may change its product lines; a card an agent cannot see
  answers 404 for its tasks too. The client sends `completed: true|false` and the server
  stamps the time. The board gets `tasks: { open, overdue, next_due_at }` per card and the
  card shows the overdue count (or the open one) as a badge.
- **Automations:** see "Sprint 5" below; the first version only moved a card.
- **Task reminders** (`Custom::Kanban::TaskReminderJob`): every minute, an open task due within
  15 minutes (or overdue by less than an hour) is announced once to its assignee, as a
  `kanban.task.reminder` cable event the dashboard shows as a toast linking to the board. The
  text is written by the server in the account's language
  (`flow_kanban.task_reminder` in `custom/config/locales`). `reminded_at` is the claim, so
  several workers never announce a task twice; a new date, or a task taken up again, is
  announced again. Only an agent who still sees the board gets it, and it reaches only an
  agent with the dashboard open: one who was away finds the overdue badge on the card. The
  engine registers the cron entry (`flow_kanban_task_reminders`) when a Sidekiq server starts,
  so `config/schedule.yml` stays upstream's.
- **Notifications** (`flow_kanban_notifications`, `kanban/notifications`, the bell in the
  Kanban toolbar): what an agent should know about their own deals when they were elsewhere,
  kept until read. `Custom::Kanban::Notifier` decides, and writes only reasons the agent can
  act on: a task of theirs due soon or overdue (the reminder job), a task or a deal someone
  else assigned to them, a deal of theirs moved by a board rule. Never their own doing, and
  never a deal on a board they cannot see; `Notification.listed_for` filters again when
  reading, so losing a board hides its notifications and getting it back shows them. The text
  is a snapshot (`data`), written when it happened, so a renamed or deleted card or task does
  not rewrite the past. A new one reaches an open dashboard as `kanban.notification.created`
  with the server's unread count, which is the badge. A row opens the deal and marks itself
  read; read ones go after two weeks, any after two months (`NotificationCleanupJob`, cron
  `flow_kanban_notification_cleanup`). Kept out on purpose: every comment, move or message
  (noise), and anything about other agents' deals.
- **Not built yet:** notifications by e-mail or push, per-agent choice of what the bell
  collects, and rules for other triggers (see ROADMAP.md).

### Sprints 0 to 2 (ROADMAP.md)

- **Account features** (`Custom::Kanban::Features`, `accounts.settings.flow_kanban_features`):
  a super admin switches behaviours per account in Super Admin → Accounts → Edit. `auto_create`
  starts off, `stale_alerts` on; an administrator still sets each one up per board.
- **Design audit** (`custom/script/design-audit.mjs`, `flow-tools/run.sh audit`): the DESIGN.md
  rules a script can see; exit 1 on a finding. A deliberate exception is written on the line
  before it in the template, with the reason (`<!-- design-audit-allow: rule (why) -->`).
- **Shared pieces:** `EmptyState`, `SkeletonRows`, `StatePill` and `SegmentedControl` in
  `flowKanban/`; no screen builds its own empty or loading block any more.
- **Usage numbers** (`Custom::Kanban::Metrics`, `rake "flow:kanban:metrics[ACCOUNT_ID,DAYS]"`):
  deals by source, automatic ones awaiting review, stalled now, tasks done late, notifications
  opened. Counts and rates only.
- **My tasks** (`GET kanban/my_tasks`, the *Tasks* view next to Board and Report): every open
  follow-up of the deals the agent can see, grouped Overdue / Today / Upcoming in the viewer's own
  day, plus done in the last week, where ticking again reopens. Administrators may switch to the
  whole team (`scope=all`; an agent asking for it gets 401). `count_only` with `today_ends_at`
  feeds the badge on the view switch. A task notification in the bell opens the task here.
- **Compact mobile toolbar:** below `md` the toolbar folds into two rows (board and alerts; view,
  search, a Filters popover with the active count, new card). Its controls are `md` (40 px):
  the WCAG 2.2 AA target minimum is 24 px; 44 px is a book guideline we chose not to force on
  Chatwoot's control sizes.
- **Automatic deals** (`Custom::Kanban::AutoDealCreator`, from `conversation_created`): per board
  (`boards.settings.auto_create`: on/off, inboxes, daily cap 1–500), a new conversation from a
  contact with no open deal on that board opens one on the first open stage, linked, assigned to
  the conversation's agent when there is one (who is told in the bell). Group conversations are
  skipped; the contact row is locked while deciding, so a retried or doubled event opens one deal.
  The card is `source: automatic` and shows "Automatic" until an agent changes it or marks it
  reviewed (`reviewed: true`). Settings show today's count against the cap.
- **Stalled deals** (`stages.stale_after_days`, 1–365, open stages only;
  `Custom::Kanban::StaleCardsJob`, hourly cron `flow_kanban_stale_cards`): a deal past its stage's
  limit shows "Stalled N d" and its agent gets one `card_stale` notification per stall
  (`cards.stale_notified_at`, cleared by any move). With the feature off, deals are left unclaimed,
  so turning it back on catches up. The board's *Situation* filter shows stalled deals or deals
  with an overdue task (`status=stale|overdue_tasks`).

### Sprints 3 and 4 (ROADMAP.md)

- **Deal history** (`flow_kanban_card_events`, `GET kanban/cards/:id/events`, a *History* section in
  the card panel): append-only, written where the change happens: creation (manual or automatic),
  stage moves (with who, or that a rule did; a stage deleted with its deals moves them too), value
  and assignee changes, tasks scheduled, completed and reopened, conversations linked, quotes
  taken to a conversation. `data` keeps names as they were, so renaming a stage later does not
  rewrite the past. Backfilled from `stage_transitions`. It is what webhooks and the AI summary
  will read (Sprints 6 and 7).
- **Lost reasons** (`flow_kanban_lost_reasons`, Settings → Kanban): a short list an administrator
  keeps. Moving a deal onto a lost stage asks why (board drag, stage picker in the card panel, the
  conversation panel) in one dialog; "No reason" and cancelling are both allowed, so the drag never
  blocks. The reason and note live only while the deal is in a lost stage. Deleting a reason keeps
  the deals and empties theirs.
- **Forecast fields:** `cards.expected_close_on` (2000 to ten years ahead) and
  `stages.win_probability` (0–100, open stages only; Won is 100, Lost 0, an unset open stage 50).
- **Report** (*Report* view): the *Revenue forecast* by close month, weighted and unweighted, with
  rows for overdue, later and no date (never dropped) and a pill when only some open deals have a
  date; and *Lost reasons* with the deals lost without one counted as "No reason".
- **Quotes** (`Send quote` in the card's value section): the message is built from the product
  lines and the account's template (Settings → Kanban, with `{{contact}}`, `{{deal}}`, `{{items}}`,
  `{{total}}`, `{{agent}}` and a live preview; empty means the default in the agent's language),
  shown for review, and put in the reply box of the linked conversation as a draft by its
  `display_id` (`draft-<display_id>-REPLY`, see AGENTS.md, "Conversation ids"). Nothing is sent
  from the dialog; `POST kanban/cards/:id/quote` only writes the history. PDF is not built.

### Sprint 5: rules that do more (ROADMAP.md)

- **A rule** (`flow_kanban_stage_automations`, `kanban/boards/:id/automations`, administrators
  only) has one trigger, up to 5 ordered steps (`actions` jsonb) and an on/off switch. Triggers:
  conversation status changed, label added, deal created, deal stalled, no reply for N hours (1 to
  720; the customer or the team is the silent side). Steps: move to a stage, create a task (title,
  type, due in 0 to 720 hours, assigned to the deal's agent or a fixed one), assign an agent, add a
  label to the linked conversations. A migration turned each old rule's `stage_id` into a
  `move_to_stage` step and is reversible.
- **Running** (`Custom::Kanban::AutomationRunner`, `AutomationAction`): a deal runs a rule once
  per trigger *episode* (`flow_kanban_automation_runs`, unique on rule, deal and episode key; the
  key is the status change time, the stall, the silent message, and so on), so a retried event or an
  hourly job never repeats it. Rules run oldest first and a later move wins. A card move never
  triggers a rule. A step that cannot apply is "skipped" with its reason (already there, no agent,
  agent cannot see the board, already assigned, already labelled, no conversation); a step that
  raises is "failed" and the next ones still run. Each rule is capped at 200 runs a day. A rule
  whose stage, agent or label was deleted is flagged *Needs attention* and does not run.
- **Time-based triggers** run from cron: `flow_kanban_no_reply` every 15 minutes
  (`NoReplyAutomationsJob`, open deals in open stages with open conversations, last 30 days) and
  the stalled rules from `StaleCardsJob`, whether or not the account's stall alerts are on. Run
  rows older than 90 days go with `NotificationCleanupJob`.
- **Run log:** every run writes an `automation_ran` card event with each step's result, shown in the
  deal's History and in *Recent runs* under the rules (`GET boards/:id/automations/runs`, the last
  50, administrators only).
- **UI** (`BoardAutomationsSection`, `AutomationEditor`, `automations.js`): the list reads as
  sentences ("When the customer is silent for 24 h: create the task ..."), with a switch, edit,
  delete (confirm dialog) and the *Needs attention* pill with its reason; the editor opens inline
  (the board settings are already a side panel) as *When* + ordered *Then* steps with up/down/remove,
  inline errors after the first save attempt and the server's message. An empty board offers three
  starters (won when resolved, chase a silent customer, fast first contact).

### Sprint 6: connect and import (ROADMAP.md)

- **Webhooks** (`flow_kanban_webhooks`, `flow_kanban_webhook_deliveries`, Settings → Kanban → Webhooks,
  administrators only, up to 10 per account): own table, so no upstream constant is touched. A webhook
  is **account-level**: it hears about every board of the account, which is why agents cannot see or
  change it. Events: `deal.created`, `deal.moved`, `deal.won`, `deal.lost`, `deal.value_changed`,
  `task.created`; a move onto a won or lost stage is both `deal.moved` and `deal.won`/`deal.lost`.
  They come from the card events ledger: `CardEvent` `after_create_commit` →
  `WebhookDispatcher` (the payload is built then, so a retry or a deleted deal still sends what
  happened) → `WebhookDeliveryJob`. Switch: the `webhooks` account feature (on by default; it sends
  nothing until an address is added).
- **Delivery:** `POST` JSON with `X-Flow-Event`, `X-Flow-Delivery` and
  `X-Flow-Signature: t=<unix time>,v1=<hex>`, where the signature is HMAC-SHA256 of
  `"<time>.<body>"` with the webhook's secret (shown once, on creation). Five attempts in all
  (after 1 min, 5 min, 30 min, 2 h) for a timeout, a 5xx, 408 or 429; any other answer is final. Only
  https is accepted, with no user:password; the address is resolved first and refused when it points
  to a private, loopback or link-local network (the connection goes to the address that was checked,
  and redirects are not followed). *Send test* sends a signed `ping` now and shows the answer; the
  log shows the last 50 deliveries and is kept 30 days (`NotificationCleanupJob`).
- **Export** (`GET kanban/products/export`, `GET kanban/boards/:id/cards/export`): UTF-8 with BOM,
  money as a plain decimal, at most 20,000 rows, and a cell that starts with `=`, `+`, `-`, `@`, a tab
  or a return gets a leading apostrophe so a spreadsheet does not read it as a formula. The deals
  export takes the board's filters (the toolbar's download button sends the ones in use) and only
  works for boards the person sees. The first columns are the ones the importers read.
- **Import** (`flow_kanban_imports`, Settings → Kanban → Import and export, administrators only):
  upload → **dry run** (columns guessed from the header, editable; the first rows with what would
  happen to each; every problem by line; nothing written) → run in the background
  (`ImportJob`, claimed once, progress polled) → result and a downloadable error file. Limits: 2 MB,
  5,000 rows, UTF-8, comma or semicolon. Products are matched by SKU (by name without one), so a
  second import of the same file changes nothing. Deals go into one board: the contact is found by
  e-mail or phone (and created when new), a deal with the same title for the same contact is skipped,
  the stage is read by name (the first open one when empty), values accept `1.234,56` and `1234.56`,
  dates `AAAA-MM-DD` or `DD/MM/AAAA`. Imported deals fire the deal-created rules and webhooks like
  any other. The file is dropped when the run ends and finished imports after 7 days.

### Sprint 7: AI summary of a deal (ROADMAP.md)

- **What it is:** a *Summarize deal* button in the card panel (the *AI summary* section, labelled
  "Generated by AI") that asks Captain for a draft summary of the deal and **one** suggested next
  task. Off by default: a super admin turns on the `ai_summary` feature per account (Super Admin →
  Accounts → Edit), and the account also needs Captain's `captain_tasks` feature and an API key.
- **Draft, never automatic:** nothing is written until the agent acts. *Add to description* puts
  the (editable) text under the description in the card form, and the card's own Save keeps it;
  *Schedule task* creates the suggested task (title, date and type editable) through the normal task
  endpoint; *Discard* throws it away. `POST kanban/cards/:id/ai_summary` only returns the draft.
- **Built on Captain's task service** (`Custom::Kanban::DealSummaryService < Captain::BaseTaskService`):
  the Captain switch, the key (an account's own OpenAI hook is preferred and then does not use the
  response quota), the quota and the instrumentation are the ones every Captain task uses.
- **What leaves the installation**, to the provider Captain is set up with (OpenAI unless
  `CAPTAIN_OPEN_AI_ENDPOINT` says otherwise): the deal's title, stage, value, close date, contact
  name, assignee and open tasks, the last 30 history events and the **public** messages of the linked
  conversations **the agent may open** (private notes, attachments and other conversations are never
  sent), at most 30,000 characters, newest first when a thread is longer (the draft says so). The
  prompt tells the model that all of it is data, not instructions.
- **Limits and failures:** 10 requests an hour per agent (`flow_kanban_ai_drafts`, counted even when
  they fail, as each one costs); no linked conversation or no public message → "nothing to
  summarize", no call made; no key, quota used up, feature off, rate limit and any other failure each
  have a plain message and leave the card unchanged. The draft text is never stored: the table keeps
  who asked, for which deal, what was used and whether it was accepted or discarded (kept 90 days),
  which is what the metric (accepted ÷ generated) reads. The draft is written in the account's
  language.

### Sprint 8: hardening (ROADMAP.md)

- **Security review of the Kanban API.** `spec/custom/kanban/security_spec.rb` walks every route of
  the Kanban API: signed out → 401; an administrator of another account → 401; an agent on every
  administrator-only endpoint (automations, webhooks, imports) → 401; no route answers 5xx to a bad
  id. A new route is covered by the sweep the day it is added. Findings fixed:
  - the webhook address check now refuses every non-public range (this host, 0.0.0.0, private and
    shared 100.64/10, link-local and cloud metadata, multicast, reserved, documentation, the IPv6
    unique-local and NAT64 forms), not only the common ones;
  - the webhook secret is encrypted at rest when the installation has Active Record encryption keys
    (as Chatwoot's own webhook secrets), and can be replaced (*New secret*: the old one stops signing
    at once, the new one is shown once);
  - decisions kept and written down: webhooks are account-level and administrator-only; the deals
    export is open to anyone who sees the board and only exports that board (the same data the
    board shows them); the AI summary sends only what the agent can open.
- **Performance.** `spec/custom/kanban/performance_spec.rb` counts the database queries of the
  board, filtered board, My tasks, report, deals export, automation runs, boards list, products
  (list and export) and webhooks with few and with many records: the count must not grow (no N+1).
  With `PERF=1` it also seeds 10,000 deals and times them: the board page 0.4 s, My tasks 0.2 s,
  the report 0.3 s, the stalled scan 0.01 s and the full export of 10,000 deals 2.9 s (1.2 MB). The
  indexes designed with each query held; no index was added.
- **Accessibility** (axe-core, WCAG 2.2 AA, light and dark, on the board, card panel, bell, My
  tasks, report, rule editor, Settings, webhook and import dialogs): from 52 distinct findings in our
  screens to none of ours. Fixed: the card was a `role="button"` around links (nested interactive
  content) and is now a group with a real *Open* button that shows on focus, so Tab reaches a card and
  Enter opens it; conversation chips are at least 24 px; checkboxes have a label; avatars next to
  a name are hidden from assistive tech and the others are named in text; the report region can be
  focused and its bar labels have a role; the file input has a name. **Faint Ink**
  (`text-n-slate-10`) failed AA as text, so DESIGN.md now keeps it for icons and `design-audit`
  rejects it on text; the stalled pill's amber text is darker. What is left in the audit is the
  Chatwoot shell, not ours: the sidebar search placeholder and two unnamed buttons, the sidebar
  profile avatar, the white-label icon without `alt` and the floating help button. The brand
  colour is chosen per account, so contrast of brand-coloured text depends on the palette.

### Phase P: the Pro dialect for the fazer.ai agents (ROADMAP.md, C0 to C4)

The agents' client (`flow-agents-ee`, the fazer.ai agents unchanged) talks to the Chatwoot Pro's Kanban
routes. Flow answers them in a compatibility layer, so the agents need no edit; the contract is
`custom/contracts/pro-kanban.md` and its schema, with the hash in `CONTRACT.sha256` (and a
`.gitattributes` that keeps those files LF, as the hash is over their bytes).

- **Measured, not assumed:** the agents' harness (`custom/harness/run.ts` there) runs their real
  `ChatwootClient` through the cycle against a running stack. Before this work 1 of 16 checks passed;
  now **10 of 16** pass: operations 1 to 5 (boards, steps), 8 to 11 (deals) and 15 (the conversation's
  deal). Waiting: 6 and 7 (`update_inboxes`, `update_agents`, C4) and 12 to 14 with the reset (priority,
  dates, labels, attributes on the card, C2).
- **Routes** (`Api::V1::Accounts::Kanban::Compat::*`): `GET|POST kanban/boards/:id/steps`;
  `GET|POST kanban/tasks`, `GET kanban/tasks/:id` (the bare card), `POST kanban/tasks/:id/move`.
  A Pro "task" is a Flow card and a "step" a stage (`cancelled` is a lost stage). Boards also take the
  `{board: {...}}` root key (a board made that way gets no default stages: the caller's steps are the
  funnel). **`GET kanban/tasks` used to be "My tasks"**: it is `GET kanban/my_tasks` now, because the
  same address answering two different types is the worst failure (the agent got a 200 with follow-ups
  where it expected deals).
- **Answers are a superset:** every field the contract requires is there (`labels: []`,
  `custom_attributes: {}`, nulls) next to Flow's own (`value_cents`, `stage_id`, `conversation_ids`);
  `value` is a number in the account's currency out and cents in, never through a float.
  `insert_before_task_id` puts the deal directly above that card of the target step.
- **The conversation's deal** (`kanban_task` in `GET conversations/:display_id`, one line in the shared
  jbuilder): the most recently updated *open* deal linked to it on a board the caller sees, else `null`.
  Only on the single read (a list would ask the database per row), only for people signed in with a
  user token, and never in what reaches a contact: the cable presenter builds that from an allowlist.
- **Announced:** every Kanban answer carries `X-Flow-Kanban-Dialect: pro-v1`, and
  `GET kanban/settings` returns `api_version`, `dialect` and `capabilities`.
- **The agents' service user** (`rake "flow:kanban:agent_bot[EMAIL]"`, `UNMARK=1` to clear): an
  administrator by role (the dialect needs one to make boards and steps) marked `flow_service: agent_bot`.
  It does everything on the deals, and nothing on webhooks, imports or automations
  (`Custom::Kanban::HumanAdministrator`), so a leaked or misled agent token cannot point a webhook at an
  attacker. The mark cannot be unset through the profile endpoint.
- **Stage description** (`flow_kanban_stages.description`, at most 120 characters): in the API only for
  now; the dashboard edits it in C2.
- **Specs:** `spec/custom/kanban/pro_dialect_spec.rb` (each operation, visibility, the leak, the service
  user) and `pro_contract_spec.rb` (the hash, and that all 15 operations are accounted for).
