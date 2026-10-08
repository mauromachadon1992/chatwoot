---
name: flow-chat
description: The Chatwoot dashboard design system as the Flow fork uses and extends it (Kanban first).
colors:
  brand: '#3E63DD'
  brand-text: '#3F64DE'
  brand-wash: '#ECF2FF'
  won-teal: '#12A594'
  won-teal-text: '#008573'
  lost-ruby: '#E54666'
  lost-ruby-text: '#CA244D'
  pending-amber: '#FFC53D'
  pending-amber-text: '#AB6400'
  ink: '#1C2024'
  ink-muted: '#60646C'
  ink-faint: '#80838D'
  ink-disabled: '#8B8D98'
  hairline-strong: '#D9D9E0'
  canvas: '#F7F7F7'
  surface: '#FEFEFE'
  solid: '#FFFFFF'
  border-weak: '#EAEAEA'
  border-strong: '#E2E3E7'
typography:
  heading-1:
    fontFamily: "Inter, -apple-system, system-ui, 'Segoe UI', Roboto, sans-serif"
    fontSize: '18px'
    fontWeight: 520
    lineHeight: '24px'
    letterSpacing: '-0.27px'
  heading-2:
    fontFamily: "Inter, -apple-system, system-ui, 'Segoe UI', Roboto, sans-serif"
    fontSize: '16px'
    fontWeight: 500
    lineHeight: '24px'
    letterSpacing: '-0.27px'
  heading-3:
    fontFamily: "Inter, -apple-system, system-ui, 'Segoe UI', Roboto, sans-serif"
    fontSize: '14px'
    fontWeight: 500
    lineHeight: '21px'
    letterSpacing: '-0.27px'
  body:
    fontFamily: "Inter, -apple-system, system-ui, 'Segoe UI', Roboto, sans-serif"
    fontSize: '14px'
    fontWeight: 420
    lineHeight: '21px'
    letterSpacing: '-0.28px'
  label:
    fontFamily: "Inter, -apple-system, system-ui, 'Segoe UI', Roboto, sans-serif"
    fontSize: '14px'
    fontWeight: 500
    lineHeight: '21px'
  label-small:
    fontFamily: "Inter, -apple-system, system-ui, 'Segoe UI', Roboto, sans-serif"
    fontSize: '12px'
    fontWeight: 440
    lineHeight: '16px'
    letterSpacing: '-0.24px'
rounded:
  sm: '6px'
  md: '8px'
  lg: '12px'
  full: '9999px'
spacing:
  xs: '4px'
  sm: '8px'
  md: '12px'
  lg: '16px'
  xl: '24px'
  2xl: '32px'
components:
  button-primary:
    backgroundColor: '{colors.brand}'
    textColor: '{colors.solid}'
    rounded: '{rounded.md}'
    height: '32px'
    padding: '0 12px'
  button-ghost:
    backgroundColor: 'transparent'
    textColor: '{colors.ink-muted}'
    rounded: '{rounded.md}'
    height: '32px'
    padding: '0 8px'
  button-destructive:
    backgroundColor: '{colors.lost-ruby}'
    textColor: '{colors.solid}'
    rounded: '{rounded.md}'
    height: '32px'
    padding: '0 12px'
  input:
    backgroundColor: '{colors.solid}'
    textColor: '{colors.ink}'
    rounded: '{rounded.md}'
    height: '40px'
    padding: '0 12px'
  kanban-card:
    backgroundColor: '{colors.solid}'
    textColor: '{colors.ink}'
    rounded: '{rounded.md}'
    padding: '12px'
  kanban-column:
    backgroundColor: '{colors.canvas}'
    rounded: '{rounded.lg}'
    width: '288px'
    padding: '8px'
---

# Design System: flow-chat

## Overview

**Creative North Star: "A Mesa de Operação"** (the operations desk)

Agents keep this dashboard open all day, triaging conversations from WhatsApp, e-mail, the
widget and every other channel, and moving deals along a funnel. The interface is the desk,
not the work: dense, calm and predictable, so the conversation and the customer are what
the eye lands on. Familiarity is a feature. A new Flow screen must feel like it shipped with
Chatwoot, built from the same components, type scale and colour tokens, and differing only
where the task demands it.

The system is Chatwoot's own (`components-next`, the `n-*` colour tokens, the typography
utilities in `_woot.scss`), light and dark from the same token names. Flow extends it; it
never forks it. Expression lives in precise details: a stage colour dot, a channel icon on a
conversation chip, a quiet hover lift on a card being dragged.

**Key Characteristics:**

- Restrained palette: neutral surfaces, one blue for action and selection, semantic colour only for state.
- Flat surfaces separated by tone and a 1px outline; shadow is reserved for things that float.
- One sans family (Inter) on a tight, fixed scale; hierarchy from weight and colour, not size jumps.
- Every control comes from `components-next`; no native form controls in Vue screens.
- Light and dark themes are the same tokens with different values: never hard-code a hex.

## Colors

A neutral, low-chroma workspace with a single action indigo and four semantic accents that only
ever mean state.

### Primary

- **Flow Indigo** (brand, `#3E63DD`): primary buttons, focus outlines (`outline-n-brand`), current
  selection, links. Its rarity is what makes the next step obvious.
- **Flow Indigo Text** (brand-text): accent text on light surfaces, where the brighter fill
  would miss contrast.
- **Selection Wash** (brand-wash): selected rows and soft accent backgrounds.

The accent is a ramp, not a hex: `n-brand` is step 9 of `--blue-1..12`, and a white-labelled
account replaces the whole ramp with its own colour (see "The Accent-Ramp Rule"). "Blue" in
this document means "the account's accent". The installation's accent is **Flow Indigo**, the seed
`#3E63DD` of the ramp (white on step 9 passes at 4.5:1 without adjusting it); Chatwoot's own blue is only
what an installation shows before the identity is applied (`rake "flow:identity:apply"`). The
Button colour prop is still called `blue`: it names the accent, whatever its hue.

**Identity.** The name is **flow-chat** (always lowercase and hyphenated), its sibling **flow-agents**; the mark
is a rounded tile with three columns stepping down, a card moving from stage to stage. Name, mark, seed colour
and voice are one document shared with the agents repository, `custom/contracts/identity.md`, and the
SVGs beside it: change them there, in both repositories. Brand stays in precise details (the login screen,
the tab title and icon, the sidebar), never in decoration on a working screen.

| Role | Token | Step |
| --- | --- | --- |
| Solid fill under white text (primary button, badge) | `bg-n-brand` | 9 |
| Hover of that fill | `brightness-110` or `bg-n-blue-10` | 10 |
| Accent text, links, icons | `text-n-blue-11` | 11 |
| Strong accent text | `text-n-blue-12`, `text-n-blue-text` | 12 |
| Focus ring, selected outline | `outline-n-brand`, `ring-n-brand` | 9 |
| Selection wash, soft fill | `bg-n-brand/10`, `bg-n-blue-3`, `bg-n-solid-blue` | 3 to 4 |
| Accent borders | `border-n-blue-7`, `border-n-blue-border` | 7, 9 at 50% |

### Secondary

- **Won Teal** (won-teal / won-teal-text): success, open conversations, won stages.
- **Lost Ruby** (lost-ruby / lost-ruby-text): errors, destructive actions, lost stages.
- **Pending Amber** (pending-amber / pending-amber-text): warnings, pending conversations.

### Neutral

- **Ink** (ink, `text-n-slate-12`): titles and primary text. Never pure black.
- **Muted Ink** (ink-muted, `text-n-slate-11`): secondary text, descriptions, field hints.
- **Faint Ink** (ink-faint, `text-n-slate-10`): icons and decoration only. It is below the AA
  contrast ratio for text, so metadata and timestamps use Muted Ink; `design-audit` rejects it on text.
- **Canvas** (canvas, `bg-n-background`), **Surface** (surface, `bg-n-surface-1`) and
  **Solid** (solid, `bg-n-solid-1`): the three layers, from the page back to the card in hand.
- **Alpha fills** (`bg-n-alpha-1`, `bg-n-alpha-2`): Kanban columns, pills, hover and pressed
  states. They are translucent, so they work on any layer and in both themes.
- **Hairlines** (border-weak, border-strong, `outline-n-container`): dividers and outlines.

### Named Rules

**The Tokens-Only Rule.** Colour comes from the `n-*` Tailwind tokens, never from a literal
hex. The only exception is user data, such as a stage colour picked in the board settings,
which is applied through `:style`.

**The State-Not-Decoration Rule.** Teal, ruby and amber always signal a state, and they are
always paired with an icon or a word. A coloured dot alone never carries meaning.

**The Accent-Ramp Rule.** Action and selection use only the `n-brand` and `n-blue-*` tokens,
in the roles above, never `n-iris`, `woot-*` or a literal blue, so a white label re-colours
every screen at once. The ramp is generated by `Custom::WhiteLabel::Palette`, which keeps
Chatwoot's lightness for every step and guarantees: white text on step 9 at 4.5:1 (a brand too
light for it is darkened, and the super admin form says so), step 11 at 4.5:1 and step 12 at
7:1 on the step-3 wash, and step 9 at 3:1 on the dark page. Put white text only on step 9 or
darker, and accent text only in steps 11 and 12. Those are the pairs the guarantee covers.

## Typography

**Body Font:** Inter (with -apple-system, system-ui, Segoe UI, Roboto, sans-serif)

**Character:** One family carries everything. Inter's intermediate weights (420, 440, 460, 520) give fine hierarchy steps without size jumps, which keeps dense screens quiet.

### Hierarchy

- **Heading 1** (520, 18px, 24px): page and panel titles. `text-heading-1`.
- **Heading 2** (500, 16px, 24px): section headings and empty-state titles. `text-heading-2`.
- **Heading 3** (500, 14px, 21px): card titles, column names, subsections. `text-heading-3`.
- **Body** (420, 14px, 21px): general text and descriptions. `text-body-main`.
- **Label** (500, 14px, 21px): form field labels. `text-label`.
- **Label Small** (440, 12px, 16px): metadata, counts, chips, captions. `text-label-small`.

### Named Rules

**The Utility Rule.** Text uses the `text-heading-*`, `text-body-main`, `text-label` and
`text-label-small` utilities. Hand-built `text-sm font-medium` combinations drift from the
scale and are not used in new code.

## Layout

Spacing follows a 4px base: 4px inside tight component internals, 8px and its multiples
between elements (8, 12, 16, 24, 32). Gaps inside a group are visibly smaller than gaps
between groups: a form uses 16px between fields and 32px between sections.

Pages are full-height flex columns: a header bar (`px-6 py-3`, bottom hairline), then the
work area filling the rest. Wide content scrolls on its own axis. The Kanban scrolls
horizontally, each column scrolls vertically, and the page itself never does.

The surface is designed for desktop, continuous use. Under 768px the header wraps and the
board keeps its horizontal scroll; there is no separate mobile layout.

## Elevation & Depth

Flat by default, with depth expressed through tonal layers (canvas, then surface, then solid)
and a 1px outline (`outline outline-1 outline-n-container`). Shadows are reserved for
elements that float above the page (dropdowns, side panels, dialogs) and for state: a card
lifts slightly on hover and while being dragged.

### Shadow Vocabulary

- **Resting card** (`shadow-sm`): Kanban cards at rest, barely separated from their column.
- **Lifted** (`shadow-md`): hover on a draggable card.
- **Overlay** (`shadow-lg`): dropdown menus, side panels, dialogs.

### Named Rules

**The Float-Only Rule.** Only overlays carry `shadow-lg`. Inline containers get a tone or a
hairline, never a large shadow.

## Shapes

Gently rounded, one language throughout: 6px (`rounded-md`) for pills, chips and small
controls, 8px (`rounded-lg`) for buttons, inputs and cards, 12px (`rounded-xl`) for columns,
panels and dialogs. Status dots and avatars are fully round. Borders are 1px outlines; a
coloured side stripe on a card is never used.

## Components

Restrained and precise: quiet at rest, unambiguous on hover and focus, colour only where an
action or a state lives.

### Buttons

- **Shape:** gently rounded (8px), from `Button` in `components-next`.
- **Primary:** `solid blue`, one per view, for the main action (such as "New card" or "Save").
- **Secondary:** `faded slate` for alternative actions, `ghost slate` for toolbar icons, and
  `link` for inline actions such as "Clear filters".
- **Destructive:** `ghost ruby` to open the confirmation, and the `Dialog` with `type="alert"`
  for the irreversible step (Cancel on the left, the red action on the right).
- **Icon-only buttons** always carry `aria-label` and a `v-tooltip`.

### Inputs / Fields

- **Text:** `Input`, `TextArea` and `InlineInput` (for in-place renames). A field icon goes in
  the `#prefix` slot.
- **Single choice in a form:** `ComboBox` (searchable list). Wrap it in `RequiredComboBox`
  when the field may not be cleared.
- **Filters in a toolbar:** `SingleSelect` from `filter/inputs`, which accepts
  `{ id, name, icon }` options and treats clearing as "all".
- **Multiple choice:** `TagMultiSelectComboBox`.
- **Two to four options:** a segmented control (`ButtonGroup` plus ghost `Button`s with
  `role="radio"`), so every option stays visible. `flowKanban/SegmentedControl.vue` is that
  pattern with text options.
- **Colour:** `ColorPicker`, saved with a debounce.
- **Labels:** a `<label class="flex flex-col gap-1.5 text-label text-n-slate-12">` wrapping the control.
- **Never** a native `<select>`, `<input>` or `<button>` in a Vue screen.

### Chips

- **Conversation chip:** `rounded-md bg-n-alpha-2`, `text-label-small`, a status dot, the
  channel icon (`getInboxIconByType`) and `#display_id`. A conversation from an inbox the user
  cannot open is shown with a lock icon and no link.
- **Count pill:** `rounded-md bg-n-alpha-2 tabular-nums`, `text-label-small`.

### Cards / Containers

- **Kanban card:** solid surface, 8px radius, 12px padding, `outline-n-container`,
  `shadow-sm` that lifts to `shadow-md` on hover. Inside, the title (`text-heading-3`, two
  lines at most), then the contact, the conversation chips and a metadata row with icon and
  text. Which fields show is chosen per account by a super admin.
- **Kanban column:** `bg-n-alpha-1`, 12px radius, 288px wide, header with a colour dot, name,
  stage-type icon, count and an add button. An empty column shows a dashed drop zone.

### Money and figures

- **Money input** (`flowKanban/MoneyInput.vue`): Chatwoot's `Input`, plain number while
  focused (either decimal mark), formatted in the account currency on blur. Values are cents.
- **Amounts** use `tabular-nums`. On the board they drop the cents (`money(v, { whole: true })`);
  in a deal's lines and totals they keep them.
- **Report strip**: one `rounded-xl bg-n-solid-2` container like Chatwoot's report metrics,
  each figure a label with an info tooltip that defines it, the value (`text-2xl`), and a
  `text-label-small` detail; figures separated by a `border-s` hairline, never separate cards.
- **Funnel table**: a real `<table>`, numbers right-aligned, the reach bar in the stage's own
  colour on a `bg-n-alpha-2` track, with the count beside it. Lost stages say "outside the
  funnel" in words, not only by a missing bar.

### Overlays

- **Side panel** (`SidePanel`): for detail and settings that keep the board in view (card
  details, board settings).
- **Tabs in a side panel** (`flowKanban/PanelTabs.vue`): when a panel passes about four
  sections, cut it. What identifies the thing (the card's title, stage and assignee) stays
  above the tabs; the rest goes one section per tab, in the order a person works: details,
  value, tasks, conversations, history. A real tablist (`role="tab"`, `aria-selected`,
  `aria-controls`, one tab in the tab order, arrow keys, Home and End), a 2px brand underline on
  the current tab, a count pill (`tabular-nums`) only where a number says what is behind it, and
  a row that scrolls sideways on a phone instead of squeezing the labels. A tab is built when
  first opened and then hidden, not destroyed, so what was typed or fetched stays. The Save
  button is the panel's, not the tab's, so a change on one tab is never lost by switching. Do not
  use the upstream `TabBar`: native buttons, `text-n-slate-10` and a fixed width.
- **Dialog** (`Dialog`): for short, focused tasks (create a card) and for every destructive
  confirmation.
- **Dropdown menu** (`DropdownMenu`): for switching context, such as picking a board.

### Feedback

- **Loading:** skeleton columns and cards (`bg-n-alpha-2 animate-pulse`), never a spinner in the middle of content.
  Rows of a list or a section use `flowKanban/SkeletonRows.vue`.
- **Empty state:** an icon tile, a `text-heading-2` title, one sentence that explains what to
  do, and the action when the user is allowed to take it: `flowKanban/EmptyState.vue`
  (`page` or `compact`, `framed` for an area that would hold content).
- **State pill** (`flowKanban/StatePill.vue`): a state said with tone, icon and words ("Overdue",
  "Stalled 6 d"). Information that asks for no action ("Automatic") takes the neutral tone: with a
  white label the blue ramp is the brand colour and would read as an alert.
- **Toasts** (`useAlert`): name what happened, or what failed and what to do next.

## Do's and Don'ts

### Do:

- **Do** build every control from `components-next`, and look there before writing markup.
- **Do** use the typography utilities (`text-heading-3`, `text-body-main`, `text-label-small`).
- **Do** keep one primary button per view.
- **Do** pair every state colour with an icon or a word.
- **Do** give icon-only controls an `aria-label` and a tooltip.
- **Do** use logical spacing (`ms-`, `me-`, `start-`, `end-`), so RTL works.
- **Do** keep strings in `i18n/fazer-ai/locale/{en,pt_BR,es}`.

### Don't:

- **Don't** use native `<select>`, `<input>` or `<button>` elements in Vue screens.
- **Don't** write a literal hex colour, except for user-chosen data applied through `:style`.
- **Don't** put `shadow-lg` on inline containers; it belongs to overlays.
- **Don't** put a coloured `border-left` stripe on cards or list items.
- **Don't** open a modal for something a side panel or an inline control can do.
- **Don't** hand-build type styles (`text-sm font-medium`) where a utility exists.
