<div align="center">

<h1>Flow Chat</h1>

<p>The Flow project's Chatwoot: WhatsApp customer support with a sales Kanban and AI agents.</p>
<p>A private fork of fazer.ai's Chatwoot, which extends the official Chatwoot. It is not the official distribution.</p>

[Português (Brasil)](README.md) · **English**

</div>

## What it is

**Flow Chat** is the Flow project's Chatwoot. It starts from [fazer.ai's fork](https://github.com/fazer-ai/chatwoot), which in turn extends the [official Chatwoot](https://github.com/chatwoot/chatwoot), and adds, in the [`custom/`](custom/) folder, a sales Kanban of its own and the conversation with **Flow Agents**, the project's AI agents (`mauromachadon1992/flow-agents-ee`).

Three layers, each with its own owner: Chatwoot (Chatwoot Inc.), the additions of fazer.ai's fork (FAZER.AI LTDA) and those of Flow Chat. Flow Chat is **not** an official Chatwoot or fazer.ai product, release, image or support channel.

## What Flow Chat adds

### Sales Kanban (`custom/`)

- Boards, stages (open, won, lost) and cards: a deal tied to a contact, with the conversations of any inbox. Drag and drop, filters, real time, and visibility by inbox, team and agent.
- Value and products: a catalog, the deal's product lines, a quote built from the card, a probability per stage, and funnel and forecast reports.
- Tasks per card, "my tasks", reminders and notifications.
- Deals that open on their own from new conversations (per account and per board), a stale-deal alert and a lost reason.
- Stage automations, signed outgoing webhooks (HMAC) and CSV import and export.
- An AI summary of the deal (Captain), off by default.
- A timeline for each card, with who acted: a person, an AI agent, a rule or the system.
- A card panel in tabs, mobile, Portuguese, English and Spanish, light and dark.

What each part does and does not do is in [`custom/README.md`](custom/README.md). The plan is in [`custom/ROADMAP.md`](custom/ROADMAP.md), and the state right now in [`custom/BACKLOG.md`](custom/BACKLOG.md).

### The conversation with Flow Agents

- Flow Chat speaks the **Kanban dialect** the agent's client already uses (15 operations; Flow Agents' harness passes 16 of 16 against it) and offers **extensions** (catalog, the deal's products, value), all behind capabilities announced in `GET kanban/settings`.
- The agent acts as a **service user** (`agent_bot`), which cannot reach webhooks, imports or automations.
- The contract, in [`custom/contracts/`](custom/contracts/), is the same in both repositories, with a single hash. The [protocol](custom/contracts/protocol.md) says who changes what, in which order, and how each side proves its part.

### What comes from fazer.ai's fork

Flow Chat inherits all of this; the details are in the [fork's README](https://github.com/fazer-ai/chatwoot#readme).

- **WhatsApp:** QR code or the official API, a native provider in beta (fazer.ai's open-source connector), groups, reactions, quoted replies, editing and deleting, phone history.
- **Internal chat between agents**, with the open edition's limits.
- **Conversations and messages:** scheduled messages, edits with history, pinned conversations, per-inbox signature, custom filters.
- **Automations and integrations:** new triggers, observer bots, a webhook per inbox.
- **Operations:** white label ([CUSTOM_BRANDING.md](CUSTOM_BRANDING.md); Flow Chat uses it for the name and the login screen), email through Resend, S3-compatible storage, sortable reports.

## Image and deploy

- **Image:** private, `ghcr.io/mauromachadon1992/chatwoot`, with the tags `<version>-<sha>-ee` (immutable, the one to pin in production), `<sha>-ee`, `<version>-ee` and `latest-ee`. It carries `enterprise/` and `custom/`. fazer.ai's public image does **not** serve: it removes `enterprise/` and has no `custom/`.
- **Build and publish:** `custom/docker/build-ee` and `custom/docker/publish-ghcr`. Run the image on your machine: `custom/docker/ee-local up` (http://localhost:3100, with its own database and Redis).
- **Coolify:** `custom/docker/coolify.compose.yaml` (production) and `custom/docker/coolify.staging.compose.yaml` (staging, with its own PostgreSQL and Redis). The walkthrough and the tags are in [`custom/docker/README.md`](custom/docker/README.md).
- **Development:** Docker, with `docker compose`; the project's rules are in [AGENTS.md](AGENTS.md) and the interface rules in [DESIGN.md](DESIGN.md).

## Updating from upstream

Flow Chat's trunk is `feat/kanban`; `main` mirrors fazer.ai's fork and gets no commits of ours. Bring upstream in by merge, preferably at a tag, and check the upstream files we touch, listed in [`custom/README.md`](custom/README.md) ("Upstream files we touch"). Back up the database before swapping the image.

## License

The original Chatwoot is copyright (c) 2017-2026 Chatwoot Inc. and uses the MIT license, except the contents of `enterprise/`, which follow the terms of [enterprise/LICENSE](enterprise/LICENSE). The `enterprise/` features (SSO, Captain, audit logs, custom roles and the rest) need a Chatwoot Inc. license in production; the AI deal summary uses Captain.

The changes and additions of fazer.ai's fork are copyright (c) 2025-2026 FAZER.AI LTDA and follow the same terms as the code they extend. Flow Chat's additions (`custom/` and the hooks listed in `custom/README.md`) derive from that code and do not change the terms of what they extend. Third-party components keep their own licenses.

When redistributing the software or substantial parts of it, keep the copyright notices and the permission notice. The requirement also applies to copies of individual files. See [NOTICE](NOTICE) and [LICENSE](LICENSE) for the full terms.

## Links

- **Flow Agents:** `mauromachadon1992/flow-agents-ee`
- **Upstream:** [fazer.ai's fork](https://github.com/fazer-ai/chatwoot) · [official Chatwoot](https://www.chatwoot.com) · [official Chatwoot code](https://github.com/chatwoot/chatwoot)
- **Support:** this repository has no third-party support; support for the original product is Chatwoot Inc.'s and fazer.ai's.
