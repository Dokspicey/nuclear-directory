# Nuclear Directory design system

Read this before building or changing any view. It holds the rules; the code lives in:

| What | Where |
|---|---|
| Tokens (color, spacing, radius, fonts, type styles) | `backend/app/assets/tailwind/design_system/tokens.css` |
| Component classes (`nd-*`) | `backend/app/assets/tailwind/design_system/components.css` |
| Icons (Phosphor, regular + bold) | `backend/app/assets/images/icons/phosphor/` and the `icon` helper (`backend/app/helpers/icon_helper.rb`) |
| Every component rendered with real markup | `/design` in development (`backend/app/views/design_system/show.html.erb`) |
| Visual reference with previews, light and dark | [Nuclear Directory design system](https://claude.ai/artifact/B1sv8wvTQTYiaKe2op1nP2) (private; ask Tosin for access) |

## Using it in Rails

- **Start from `/design`.** Copy a component's markup from `show.html.erb`, then swap in real data. Don't restyle a component inline; change `components.css` so every screen gets the fix.
- **Colors** are Tailwind utilities named after the tokens: `bg-paper`, `bg-paper-raised`, `bg-paper-sunken`, `border-rule`, `border-control`, `text-ink`, `text-ink-muted`, `bg-inverse`, `text-on-inverse`, `text-critical`. In CSS, use the raw variables: `var(--nd-paper)`, `var(--nd-ink)` and so on. Never write a hex value or a Tailwind palette color (`gray-500`, `black`) in a view. Dark mode comes for free from the variables.
- **Type** uses the `type-*` utilities, never hand-built size, weight and family: `type-display`, `type-numeral` (the 404 page's numeral only), `type-title-lg`, `type-title-md`, `type-body`, `type-body-strong`, `type-ui`, `type-small`, `type-label`, `type-data`, `type-data-sm`.
- **Spacing:** Tailwind's default scale is already 4px-based, so `gap-2` is `space-2` (8px), `p-4` is `space-4` (16px), `gap-6`, `p-8`, `py-12`, `gap-16` likewise. Stick to 1, 2, 3, 4, 6, 8, 12 and 16. Page width: `max-w-content`; running text: `max-w-prose`.
- **Radius:** `rounded-sm` (3px) for controls and chips, `rounded-md` (6px) for cards and panels, none for tables and banners.
- **Icons:** `<%= icon("flag") %>`, `<%= icon("graph", weight: :bold) %>`, `<%= icon("check", size: 12, label: "Verified") %>`. Sizes are 12, 16, 20 or 24. Pass `label:` only when the icon carries meaning without a word next to it (rare). To add an icon, copy both weights from Phosphor 2.1.1 into the two folders under the same name.
- **Component classes:** `nd-btn` (Button), `nd-search` (SearchField), `nd-select` (a filter dropdown), `nd-table` (DirectoryTable), `nd-badge` (VerificationBadge), `nd-conf` (ConfidenceMeter), `nd-src` (SourceChip), `nd-profile` (ProfileHeader), `nd-overview` (OverviewPanel), `nd-bucket--<slug>` (a bucket's accent and tint, from `--nd-cat-<slug>` tokens; Plants and sites has none) and `nd-bucketchip` (a bucket on a company page), `nd-notice` (EmptyState: one line and an action, used by the `empty_state` partial), `nd-mono` (organization initials), `nd-tag` (role and technology tags), `nd-footer` (site footer), `nd-prose` (short fixed pages such as Privacy: a narrow column of headed sections), `nd-code` (a literal block, such as a user agent or robots.txt lines). The admin (#86, behind sign-in) adds `nd-flash` (a 1px ink box; an alert adds `warning-circle` and bold text, like `nd-alert`), `nd-check` (checkbox; fields use the shared `nd-field` + `nd-input` from the corrections form, with `type-input`, 16px on phones), `nd-item` (the edit page) and `nd-kv` (a fact's values; stacked on phones). Admin v2 (#201, [canvas A](https://claude.ai/artifact/QTY5TbdsJTjbH5msHmx3LH)) adds `nd-shell` (the left nav of stages with counts, folded behind Menu on phones), `nd-tiles` + `nd-tile` (stage counts; `--ink` for the one to act on), `nd-numtable` (a table of counts), `nd-fchips` + `nd-fchip` (filter chips with counts), `nd-waits` + `nd-wait` (one waiting item: label, subject, value, buttons, details), `nd-split`, `nd-factcard`, `nd-panel` and `nd-fold` (the fact page), and `nd-btn--outline` and `nd-btn--danger`. Its corners are square and its controls 44px, as drawn. Its type utilities are `type-admin-h1`, `type-admin-h2`, `type-count` (Anton beside a heading), `type-kicker`, `type-tile`, `type-tile-sm`, `type-subject`, `type-change` and `type-cell-num`; they're for the admin only. They set layout only; type comes from the `type-*` utilities.
- **Shared partials** (`backend/app/views/shared/`): build public pages from these instead of copying markup. `site_header`, `category_pills`, `category_boxes`, `company_row`, `plant_row`, `profile_header`, `fact_row`, `source_chip`, `sources_list`, `confidence`, `verified_badge`, `overview_panel`, `missing_fields` ("Not verified yet"), `empty_state`, `site_footer`. Each one leaves out a field that's empty rather than showing a placeholder. `/design` renders each with mock records, with its optional fields filled and again with them empty. Wording (relationship verbs, plant types and statuses, role names, confidence words) lives in `DirectoryHelper`; the buckets and Plants and sites live in `Category`, bucket membership in `Bucket`, tag pages in `Tag`.
- **Public pages show verified facts only.** Pending and rejected badges belong to the maintainer queue.

Token names below (`paper`, `ink-muted`, `space-4`, `radius-sm`, ...) are the same names as the utilities and `--nd-*` variables above.

## What the product is

Nuclear Directory is a free, public reference to the US nuclear industry: who makes fuel, who builds and services reactors, who runs the plants, who buys the power and who funds it. Every fact links to its source. The design has one job: make that data feel as trustworthy as it is. It should read like a serious reference work, not a startup landing page.

The system is **monochrome**. Ink on paper, a gray scale, hairlines and three typefaces (Anton and Roboto Serif from techequity.us, plus Roboto Mono). Color comes from content (an organization's own logo, if we ever show one), never from the interface. The single exception is `critical`, which marks errors and nothing else: form errors, and in the admin a rejected fact or a failed pipeline run.

## Principles

1. **Sources are first-class UI.** Every fact on a profile carries a `SourceChip`: where it came from and when it was checked. Provenance is part of the layout, never a footnote.
2. **Dense but calm.** Researchers want a lot on screen. Get density from type hierarchy and hairlines, not from boxes, color or icons.
3. **Neutral and credible.** No nuclear clichés: no glowing green, no radiation trefoil, no atom icons (the site icon is the one exception, see Iconography), no gradients, no hype words.
4. **One system.** Every screen is built from these tokens and components, in light and dark.

## Content fundamentals

- **Voice:** plain, factual, third person. Write like an encyclopedia entry, not marketing. "Develops fluoride salt-cooled high-temperature reactors." Not "Pioneering the future of clean energy."
- **Casing:** sentence case everywhere, including buttons and section headings ("Suggest an organization", not "Suggest An Organization"). Uppercase only in Anton (`display`, `title-lg`) and the `label` style.
- **Numbers:** always in `data` (mono, tabular). Units after a thin space: `1,150 MWe`, `19.75% U-235`. Dates as `2026-10-09` in data contexts, "Oct 9, 2026" in prose.
- **Industry terms:** use them exactly: HALEU, SMR, offtake agreement, docket number, NRC construction permit. Don't explain them inline; link to a glossary later.
- **Relationship verbs** are fixed and always read left to right: *supplies*, *invests in*, *offtakes from*, *owns*, *operates*, *vendor for*. "Centrus Energy supplies TerraPower", never "TerraPower ← Centrus".
- **No people data.** No individual names, emails or phone numbers anywhere, including sample content.
- **No emoji.**

## Visual foundations

### Color
- Page: `paper`. Cards and panels: `paper-raised` with a `hairline` border in `rule`. Table headers, inputs and row hover: `paper-sunken`.
- Text: `ink` for anything a person reads first (names, values, numbers); `ink-muted` for labels, metadata and source chips. There is no third text gray. If something matters less than `ink-muted`, remove it.
- Solid fills use `inverse` with `on-inverse` text: the primary button, the verified badge, the active filter chip, the selected graph node and the profile banner. Use it at most once per region so it stays a signal.
- Control edges (inputs, checkboxes, secondary buttons) and graph edges use `control`, which holds 3:1 on every paper token. `rule` is for decoration only.
- `critical` is reserved for form errors, the rejected state in the maintainer queue, and a failed pipeline run in the admin, always next to a word.
- **State is shown by shape and words, not color.** Verified = solid `inverse` badge. Pending = dashed `control` outline. Rejected = struck-through text with the word "Rejected" in `critical`.

### Type
Fonts come from techequity.us.
- **Anton** (`display`) for the loudest moments only: the wordmark, and `display` for a home headline if one is ever needed. Company and plant names are set in Roboto Serif (`nd-profile__name`), not Anton. Always uppercase, weight 400, never bold or italic. Never more than one Anton element per screen region.
- **Roboto Serif** (`text`) for everything you read and operate: `title-md`, `body`, `body-strong`, `ui`, `small`, `label`.
- **Roboto Mono** (`mono`), from the same Roboto family, for everything you compare or copy: `data` and `data-sm`. Docket numbers, capacities, dates, counts and source domains.
- Never set running text or a number in Anton, and never set a heading in mono. One exception: the 404 page's large "404" (`type-numeral`), a decorative display element hidden from screen readers, with the page's real heading in Roboto Serif below it.

### Spacing and layout
- 4px base: `space-1` 4 · `space-2` 8 · `space-3` 12 · `space-4` 16 · `space-6` 24 · `space-8` 32 · `space-12` 48 · `space-16` 64.
- Pages max out at `content-max`; running text at `prose-max`.
- Gutters: `space-4` on phones, `space-8` on desktop.
- Tables and lists get density from `space-3` cell padding and `rule` dividers, not zebra stripes.

### Shape
- Radii stay small. `radius-0` for anything that reads as a document (tables, the banner, the graph canvas), `radius-sm` for controls and chips, `radius-md` for cards and panels. Nothing is pill-shaped except graph nodes, which are circles.
- **No shadows.** Elevation is a `hairline` border plus a step in paper tone.
- Focus: a `focus-width` ring in `focus`, offset 2px. Never removed.

### Motion
- 120ms ease-out for hover and press, 200ms for panels opening. No entrance animations. Graph nodes settle once on load and then stay put. Respect `prefers-reduced-motion` by cutting all of it.

## Key screens

The approved high-fidelity designs are on the [Nuclear Directory Screens canvas](https://claude.ai/artifact/85Lq8zzKaeqp9wvjudHhqW) (private; ask Tosin for access). Where this table and the canvas differ, the canvas wins.

| Screen | Pattern | Reference |
|---|---|---|
| Home | One job: search. Wordmark, one large `SearchField` with instant results grouped as Companies and Plants and sites, four suggested searches, a box for each bucket with companies and Plants and sites below. No intro text. | Google, Wikipedia |
| Directory and search results | One page. Compact search in the header, the buckets with companies and Plants and sites as pills, a heading with the count, Technology/State/Sort, then a dense list of rows that link to each page. No CSV export in v1. | Global Energy Monitor tracker, Fonts In Use |
| No results | One line that names the query, with "Clear search" or "Suggest a company" | Cosmos "not on Cosmos" |
| Company page | One scrolling page, no tabs: `ProfileHeader` (initials, name, one-line description, tags), Deals and links, Plants and sites, Sources; `OverviewPanel` on the right. The black banner was dropped in the approved design. | Parallel company profiles, Wikipedia |
| Power plant page | Same layout as the company page, for a site: `ProfileHeader` (ring, name, type, status, technology), Companies (owners, operator, reactor developer, power buyers), Units as a table that becomes cards on phones, Sources; `OverviewPanel` on the right. A unit's address goes to its row on the site's page. | Global Energy Monitor wiki, Wikipedia |
| Relationship map | Not built yet; the connections view (Design canvas, Oct 2026) replaces the earlier `RelationshipGraph` sketch: selected record in the center, arrows from giver to receiver, details on tap | Memotron graph, Fibery workspace map |
| Landscape view (later) | The whole graph at once, for the home page only | Delphi |

## Categories

Home and the directory show the nine buckets of companies (docs/DATA.md section 4, #281) plus Plants and sites, in visitors' words (see `VOICE.md`). A bucket is presentation only: `Bucket` computes it from published, sourced roles and links, and nothing is stored. A company appears in every bucket its facts put it in; a bucket with no companies is hidden from the pills, the home boxes and the sitemap. Slugs never change once launched: a bucket that took over an older category keeps its slug.

| On screen | Slug | What it selects | Order |
|---|---|---|---|
| Developers | `reactor-developers` | roles `reactor_vendor` or `project_developer` (designs reactors or develops new nuclear plants) | 1 |
| Fuel and materials | `fuel` | roles `fuel`, `coolant` and their children, `isotopes` | 2 |
| Components and manufacturing | `components` | role `components` | 3 |
| Waste and decommissioning | `waste-decommissioning` | role `waste_decommissioning` | 4 |
| Power plant owners and operators | `utilities` | roles `utility` or `operator`, or a current owns or operates link to an operating power reactor | 5 |
| Plants and sites | `plants` | facilities, not organizations: sites only, units sit under them (all facility types) | 6 |
| Power buyers | `power-buyers` | role `data_center_offtaker`, or the buyer in a power deal, unless it's a utility | 7 |
| Services and engineering | `services` | roles `reactor_services` or `regulatory_consultant` | 8 |
| Investors | `investors` | role `venture_capital`, or the funder in an *invests in* or *funds* link, unless it's government | 9 |
| Government and research | `government-research` | roles `government_agency`, `national_lab`, `university` or `research_organization` (EPRI) | 10 |

Where one label fits (the breadcrumb, a company's link card), a company shows its first bucket in this order. Its page lists them all under "Type".

Each bucket has an accent colour, a tint and a line icon (`icon("bucket-<slug>", set: :nd)`; Design's handoff on #322). The icon sits in the accent beside the name in pills and home boxes; a selected pill and a company page's chips use the tint behind the accent. Colour only marks a category, never status or importance, and always sits beside the icon and name. Plants and sites stays ink. Kinds of site have their own line icons (`site-*`, chosen by `site_icon_name`) in the ring on plant rows, search results and the plant page.

Tags have their own list pages but aren't navigation (`Tag`): `/companies?tag=fusion` (technology `fusion`), `?tag=uranium` (role `mining`) and `?tag=isotopes`. The old Fusion category address redirects to the fusion tag page. Each box shows two or three real example names, picked from the most connected verified organizations in that bucket.

## Relationship map visual language

- **Nodes:** an organization is a solid circle (`inverse` when selected, `ink` otherwise). A facility is a hollow circle with a `control` stroke, so organization and facility differ in shape as well as fill.
- **Edges:** 1px `control` lines. *Supplies* and *vendor for* are solid. *Invests in* is dashed (4 4). *Offtakes from* is dotted (1 3). *Owns* and *operates* are solid with a small arrowhead. Every edge type carries a `data-sm` label on hover; never tell types apart by color alone.
- **Selection:** clicking a node fills it `inverse`, raises its edges to `ink` and opens its summary in the detail panel without leaving the map.
- **Labels:** org names in `small`, `ink`; never truncate inside the canvas. Hide labels below a zoom threshold instead.

## Components and alignment

Every page is built only from these components, in the order its page entry gives (Information architecture). The canvas has each one drawn with the site's own CSS: [Components and alignment](https://claude.ai/artifact/AyVhJjG4kLvYBmXdcHeAAb) (private; ask Tosin for access), 18 Oct. Approved by Tosin, 18 Oct. Nothing a page shows today is removed by these rules; they only align, space and restyle.

### Alignment rules

These hold in the key facts panel and in every component that pairs a label with a value.

- **Two edges, each shared.** When a value sits beside its label, every such value starts on the value column's edge. When it sits under its label (a row of chips, a list of names, and every row on phones under 480px), it starts on the label's edge. Text, a link, a list, a number and a chip all follow the same rule.
- **Chips are optically aligned.** A chip's first glyph (its icon, or its first letter when it has none) sits on the value edge. The pill's padding hangs into the gutter. No component pushes a value right with its own padding.
- **Label to value: 4px (`--nd-space-1`)** when the label sits above its value (phones, and any stacked row at every width). Never negative and never collapsed.
- **Row to row: 12px**, on phones and desktop: the 4px row gap plus 8px (`--nd-space-2`) above each label.
- **Side by side (desktop):** the label column, a 16px gap (`--nd-space-4`), then the value edge. A value that needs more room than the value column (a list of two or more names, a row of chips) goes under its label at the panel's full width, with the 4px gap.
- **Source markers** follow their value on the same line and never start a line (the one-line rule). They never move the value edge.
- **Checked in tests:** the no-wrap audit (`test/support/no_wrap_audit.js`) also checks that each value's first text or glyph sits on its own edge (value column or label) to within 1px, and that each label-to-value gap is the token. A hanging pill stays inside the panel at 390.

### Source markers in key facts

**A company's own sources show once; a row has its own markers only when that fact has its own source.**

- Under the key facts, one line links the record's own evidence. It names a fact only when something enforces that one of the listed sources states the value shown: the loader, or a check when the page is drawn (#407). A production snapshot isn't enough.
  - **Company:** "Legal name: from these sources together 1 2 3" when the page shows a legal name; the loader keeps one only when a quote contains it word for word. "Headquarters" joins it ("Headquarters and legal name: …") only when #407's check finds a record quote that states the city and state shown; the loader doesn't enforce that. Website and other names aren't guaranteed a quote, so they aren't named. With nothing to name: "About this company: sources 1 2 3".
  - **Plant:** "About this plant: sources 1 2", from the site's own evidence. Docket and location are named once a check confirms a site quote states them (#407); type and status once #398 lands.
- "Together" says the sources back the named facts as a set, not each source each fact. Record evidence doesn't record which field it backs yet (#398).
- The numbers are the Sources list's, in reading order, so the description's markers and the line share them. Nothing is dropped: the line is the same set of record sources each of those rows showed.
- Role, technology, link and unit evidence keep their markers on their own rows, and aren't repeated in the line.
- Every source still appears once under Sources, linked, with its checked date.
- When #398 lands and record evidence names the field it backs, each of those rows (Headquarters, Legal name, Website, Also known as; on plants Type, Status, Location, NRC docket) gets its own markers back. The line then holds only the sources that back no single field.

### Type chip in key facts

The Type row is stacked at every width. Its chips sit 4px under the label (no negative margin). The pill hangs left by its own 8px padding, so the category icon sits on the value edge.

### Inventory

Spacing in px with its token; a value with no token is listed under "Not yet to the rules", to fix when the component is next touched.

| Component | Class | Anatomy | Spacing | 390 | 1440 | Not yet to the rules |
|---|---|---|---|---|---|---|
| Key facts panel | `nd-overview` | label (`dt`), value (`dd`), `__line`, `__val`, `__cites`; `__keep` and `__last` for a list's last name; `__stack`; `__foot`; `__fix` | padding 24 (space-6); gap 12 row, 16 column; foot 16 above | one column, label above value | label column and value column; lists and chips stacked | the stacked row's −8px margin; the 2px phone label gap |
| Type chip | `nd-bucketchip` | category icon, `__full`, `__short` | padding 2 10 2 8; icon gap 6; chips gap 4 and 8 | stacked, full width | stacked, full width | the text starts 30px in from the value edge |
| Source marker | `nd-src` | number linked to `#source-n`; in fact rows, the domain and checked date | padding 1 6; 4 before (space-1); 44px tap area on touch | same | same | record sources repeat on every record row |
| Crumbs | `nd-crumbs` | links separated by " / " | none | one line | one line | no spacing tokens |
| Profile header | `nd-profile` | mark (56px), name, summary with its sources, role tag row (`nd-tag`) | gap 16 and 20; main gap 10 | mark above the name | mark beside the name | 20 and 10 aren't tokens |
| Fact row | `nd-factrow` | who → what, detail, quote (`nd-quote`), side (sources, confidence, Report a correction) | padding 14 0; gap 6 and 16 | one column, side wraps under | two columns | 14 and 6 aren't tokens |
| Units table | `nd-table--cards` | header, cells; a Sources column when any unit is sourced | th 8 16; td 12 16 | each unit a card (label 9rem, value) | table | the card's value edge differs from key facts |
| List row | `nd-listrow` | mark (40px), name, description, capacity (plants), side (place, connections) | padding 14 4; gap 4 and 16 | side moves under the text | three columns | 14 isn't a token |
| Category pills | `nd-pill` | pill and count | padding 7 12; gap 8 | one row, scrolls, fades | wraps | 7 isn't a token |
| Category box | `nd-cat` | name, examples, count (desktop head) | padding 14 16 (12 on phones) | stacked | grid | 14 isn't a token |
| Section head | `nd-sec-h` | title and count | 12 above | same | same | |
| Sources list | `nd-sources` | number, title, domain, checked date | row padding 10 0; gap 2 and 8 | a sheet on touch (`nd-sheet`) | list | 10 and 2 aren't tokens |
| Show more | `nd-more` | button under a long list | 8 above; 44px tall | same | same | |
| Empty state | `nd-notice` | one muted line, optional action | | same | same | |
| Missing facts | `nd-gaps` | what isn't sourced yet, each with Report a correction | | same | same | |
| Today steps (admin) | `nd-tiles--stages`, `nd-numtable` | four stage tiles; counts per source | td 12 14; th 10 14 | tiles become 72px rows | four tiles | 14 and 10 aren't tokens |
| Connections map | `nd-map`, `nd-notes` (#400) | the map, then the details card, Notes and "Show connections as a list" under it | | after key facts; two or three nodes to a row, alternate rows staggered | full width under the profile header | |

Every page also has the site header (`nd-sitebar`: wordmark and search box; not on Home), the footer (`nd-footer`) and the page frame (`nd-page`). Other negative margin to remove when touched: `nd-listhead` (−24px).

### Components by page

Square brackets mark a component shown only when its data exists, or one that's approved and coming.

- **Home (`/`):** wordmark; search box (large); suggestions; category boxes (a zero count hides its box); footer.
- **Company list, category and tag pages (`/companies`, `?category=`, `?tag=`):** header; category pills (current on a category page); list head; filters (a sheet on phones); list rows, or the empty state; [with a search, two groups]; footer.
- **Company profile:** header; crumbs; profile header; key facts (Type, record facts, roles, technology, headquarters, founded, parents, subsidiaries, source line); [connections map: after key facts on phones; on desktop it runs full width under the profile header, above key facts and the lists]; the category's own sections; Deals and links; Plants and sites; [missing facts]; Sources with the cite line; Report a correction; footer.
- **Plant profile:** header; crumbs; profile header; [owner and operator sentence]; key facts ("About this plant" line); [connections map: after key facts on phones; on desktop it runs full width under the profile header, above key facts and the lists]; Companies; units table; [missing facts]; Sources; footer.
- **Unit:** its row on the plant page, highlighted.
- **Search:** instant results (group label, rows with a 32px mark); no results, or All results.
- **Report a correction:** [alert]; what you're correcting; the form; Send; back link.
- **Today (admin):** admin shell; date head; stage tiles; [counts per source]; [step 3 lists, #373].

## Iconography

- The icon set is **Phosphor** (MIT licence), chosen because one family gives two matching weights. The files the site uses so far are in the `Icons` asset group.
- **Regular** for everything on paper: controls, chips, lists, search. **Bold** only inside solid `inverse` badges and fills, and next to Anton.
- Sizes: 16px in buttons, chips and table cells; 12px inside badges and source chips; 20px in the search field and lists; 24px in empty states. Use the `nd-ic` classes.
- Icons take `currentColor`: `ink` by default, `ink-muted` beside metadata, `on-inverse` on the banner. Inline the SVG so the colour follows the text.
- Fixed meanings: `magnifying-glass` search · `sliders-horizontal` filters · `graph` relationship map · `buildings` organization · `factory` facility · `link` source · `arrow-square-out` opens a source · `check` verified · `clock` pending · `x` rejected · `map-pin` location · `coins` investment · `plug` power and offtake · `flag` report a correction · `download-simple` export · `warning-circle` something that didn't go through: an admin action, or a failed pipeline run (always next to words; never for an advisory notice such as the 80% budget line). Don't reuse one for another meaning.
- Icons support a word; they never replace one. Status and relationship types are always written out.
- Never use atom, radiation or lightning icons. The one exception is the site icon (favicon and home-screen icon): a nucleus with two crossed orbits, paper on ink, drawn by `backend/script/build_site_icon.py`.

## Logos

- There is no Nuclear Directory logo yet. The name is set in Anton, uppercase, "NUCLEAR DIRECTORY", and served as an SVG of the letter outlines (`shared/_wordmark`, built by `script/build_fonts.py`) so the font never delays the header. Put the name beside it as text for screen readers.
- Fonts are self-hosted Latin subsets (`shared/_fonts`); only Roboto Serif is preloaded.
- Organizations get a **monogram**: their initials in `mono` on a `paper-sunken` square with a `rule` border. Their own logos are inconsistent in quality, so monograms keep the directory even. If logos are added later, show them grayscale.

## Accessibility

- WCAG 2.2 AA. `ink` and `ink-muted` hold at least 6:1 on every paper token in both themes; `control` holds 3:1 for control edges.
- Full keyboard navigation, including the graph (Tab moves between nodes, Enter selects).
- Every state and relationship type is told apart by words and shape, never by color alone.
