# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

The team that owns the installation: the sales people and support agents of the company running
it (first of all Freitas Casa e Construção), working construction-materials and works deals
through WhatsApp and the other inboxes of the day-to-day operation. Administrators set up boards,
products, branding and rules; agents work conversations and deals inside the boundaries of the
inboxes and teams they belong to. Offering the product to other companies is not a stated goal
today; white label per account exists so the same installation can wear a client's name when
that happens.

## Product Purpose

Flow Agents is a fork of fazer.ai's Chatwoot that adds what a sales-led conversation business
needs on top of the inbox: a Kanban of deals, their value and products, a funnel and revenue report,
follow-up tasks, rules that act on a deal when something happens, quotes, webhooks, CSV import and
export, and an AI draft that summarizes a deal on request. Success is an agent who never
loses a deal between a chat and a spreadsheet, and an administrator who can read the funnel
without leaving the tool.

## Positioning

The deal belongs to the contact, not to a conversation or a channel: one card gathers the
conversations of any inbox, with its value, products and follow-ups beside them. It runs on the
native WhatsApp connector and pairs with AI agents (fazer.ai Agents, or Chatwoot's own Captain,
whichever is consistent with the purpose), and each account can carry its own brand.

## Operating Context

- Developed locally in WSL with Docker; the production image is built from the fork's
  `feat/kanban` branch and published privately to `ghcr.io/mauromachadon1992/chatwoot`.
- Runs on Coolify: a staging service first, then production on shared PostgreSQL and Redis.
- fazer.ai merges arrive every one to three days; `main` mirrors upstream and the fork's own
  code lives in `custom/`, so upstream files are touched only by minimal hooks.
- Conversations arrive through WhatsApp (native connector and Baileys) and the usual Chatwoot
  channels.

## Capabilities and Constraints

- Shipped: boards, stages and cards (drag and drop, filters, realtime, conversation side panel),
  deal value typed or summed from product lines, an account product catalog, one currency per
  account, stage history and the funnel report, card tasks, stage automations, and white label
  per account with the installation's own login page.
- Visibility follows conversations: an agent sees the cards of boards shared with their inboxes
  or teams, administrators see all.
- Strings live in `pt_BR`, `en` and `es` together; Portuguese is the working language.
- The Enterprise plan comes from a Chatwoot Inc license through the Hub, not from this fork.
- Undecided: whether AI agents are fazer.ai Agents or Captain for each use; reminders for tasks
  about to fall due are being added now.

## Brand Commitments

The fork keeps Chatwoot's design system and extends it (`DESIGN.md`); a white label re-colours it
per account, so brand colour comes from tokens and never from a literal. Name and logo are the
account's own once white label is on.

## Evidence on Hand

- Dev demo board "Vendas de obra" with sample contacts, cards and tasks (`tmp/flow_demo_seed.rb`).
- `custom/README.md` documents each phase; `DESIGN.md` and `.impeccable/design.json` document the
  interface.
- No customer testimonials, benchmarks, pricing or usage numbers exist; future work must not
  invent them.

## Product Principles

1. The deal outlives the conversation: anything a card shows must hold across inboxes.
2. Quiet and familiar: a Flow screen should feel like Chatwoot shipped it, with detail only where
   an action or a state lives.
3. An agent sees only what their inboxes and teams allow; no screen, count or notification
   leaks a card they cannot open.
4. Every change saves where it is made and every other open screen hears about it.
5. Build in `custom/` and touch upstream with the smallest hook, so the next merge stays cheap.

## Accessibility & Inclusion

WCAG AA: contrast of at least 4.5:1 for text, full keyboard use, screen-reader names on every
control, and a state never carried by colour alone. Portuguese first, with English and Spanish
shipped together.
