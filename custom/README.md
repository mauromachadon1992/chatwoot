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
| `app/views/layouts/vueapp.html.erb` | inlines the white label's accent ramp on the account's own domain |
| `.husky/pre-commit` | `xargs -r`, so a commit without Ruby files does not run rubocop on the whole repo |

On a `db/schema.rb` conflict, take upstream's version, then run `rails db:migrate` to dump
it again with our tables (and keep the larger schema version).

## Design system

`DESIGN.md` (repo root) documents the Chatwoot dashboard design system as this fork uses it:
tokens, the typography utilities, `components-next` usage and the do's and don'ts. Every new
screen follows it. `.impeccable/design.json` carries the extensions (dark values, shadows,
motion, component snippets) for design tooling. Both files exist only in this fork, so
merges from upstream never touch them.

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
  `app/javascript/dashboard/stores/specs/flowKanban.spec.js`.
