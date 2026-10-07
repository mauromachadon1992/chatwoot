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
| `app/dashboards/account_dashboard.rb` | super admin fields: Kanban card fields, white label status |
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
- **Automations** (`flow_kanban_stage_automations`, `kanban/boards/:id/automations`, administrators
  only): when a linked conversation reaches a status, or receives a label, the card moves to
  the rule's stage. The target stage must belong to the board. `Custom::Kanban::StageAutomationRunner`
  runs from the conversation listener, so a card move never triggers a rule: the oldest
  matching active rule wins, a card already in that stage is left alone, and the move goes
  through `Card#move_to!`, so the stage history the funnel report reads stays right. A label
  rule fires only when the label is new on the conversation (`cached_label_list` in the
  event's `changed_attributes`).
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
- **Not built yet:** notifications by e-mail or push, a task filter on the board, per-agent
  choice of what the bell collects, and rules for other triggers.
