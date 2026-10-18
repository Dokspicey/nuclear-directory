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

## Information architecture

What each page type is for, in order of importance. Build and review pages against this. The canvas has the same content, with 390 and 1440 wireframes and the fold marked: [Information architecture](https://claude.ai/artifact/3dL2vxHJV5DKUaDH2G2JVn) (private; ask Tosin for access), 18 Oct.

**Who the site is for:** Analysts, journalists, investors, policy staff and job seekers researching the US nuclear industry.

**Sitemap:**
- **Browse:** Home → category pages (9 categories + Plants and sites) → company and plant profiles. A unit is a row on its plant page.
- **Find:** the search box on every page; the company list (`/companies`); technology pages (`/companies?technology=…`, new).
- **Use and fix:** the footer's text pages (Privacy, Disclaimer, Our crawler); The data (`/data`, coming); Report a correction (from every profile).
- **Admin (signed in):** Today (#373), Sources, Live, Removed, Where it appears, record pages, correction requests.

**Two rules from Founder (18 Oct):**
- A plant page says plainly who owns it, who operates it and whether they're the same company, in one sentence under the name.
  - **The sentence shows only what's sourced.** It's built from the signed, sourced owns and operates links, and nothing else.
    - Both sourced: "Owned by X. Operated by Y, a different company." or "Owned and operated by X."
    - Only the operator sourced: "Operated by Y." on its own. Many operating plants are like this today, until the EIA-860 owners load.
    - Only owners sourced: "Owned by X."
    - Neither sourced: no sentence.
  - **Never** write "owner unknown", and never infer an owner (for example, from the operator or a parent company).
- A reactor developer's key facts include its **licensing stage**, sourced to the NRC docket. Data Quality is defining the field.

### Home (`/`)

Start a search, or browse the industry by category. **For:** Anyone arriving from a link or a search engine; returning visitors who know what they want.

- **Questions, in order:** 1. Can I find this company or plant here? 2. What does the directory cover? 3. Who are the main companies in each area?
- **Sections, top to bottom:** Wordmark; Search box + suggestions (desktop only); Category cards: 9 categories + Plants and sites (5×2 desktop; open, collapsible stack on phones); Footer.
- **Above the fold:** at 390, wordmark, search, the first category card and the top of the second. At 1440, the whole page, footer included (no scroll at 1440×900 and 1280×800).
- **Key facts and sources:** Count per category: published companies (plants for Plants and sites); Top 3 per category: most sourced connections; investors by funded companies; Short labels: Components, Waste, Services, Government, Plant operators (homepage only).
- **Links in:** Search engines and shared links; The wordmark on every page. **Links out:** Category pages (card header, See all); Company and plant profiles (card rows); Search results.
- **Cut:** Any headline or marketing copy above search; "How we pick these names" (removed 17 Oct); Counts in phone card headers.
- **Spec:** #362

### Company list (`/companies`)

See every company in one list, then narrow it. **For:** People scanning the whole industry or building a shortlist.

- **Questions, in order:** 1. Who's in the directory, and how many? 2. Which ones work in a technology or a state? 3. Which are the most connected?
- **Sections, top to bottom:** Header: wordmark + search; Category pills (sideways scroll); Title + count: All companies 89; Filters: Technology, State, Sort (one Filters button on phones); Rows: mark, name, one-line description, place, connections; Next page; Footer.
- **Above the fold:** at 390, header, pills, title and count, the Filters button, the first 4 rows. At 1440, header through about 9 rows.
- **Key facts and sources:** Name; one-line description (sourced, ellipsis past one line); Headquarters as City, ST; Connection count (published links).
- **Links in:** Footer and crumbs; Category pills on every list. **Links out:** Company profiles; Category pages; Technology pages.
- **Cut:** Descriptions longer than one line in rows; A second count in the filter bar.
- **Spec:** #263, #369

### Category page (`/companies?category=fuel`)

Everyone in one part of the industry (e.g. fuel and materials), most connected first. **For:** Someone who arrived from the homepage card or a search for "nuclear fuel suppliers".

- **Questions, in order:** 1. Who works in this area? 2. What does the category include? 3. Which are the biggest or most connected?
- **Sections, top to bottom:** Header + pills (current category selected); Title with category icon + count; One-line definition from the category's 'about'; Filters; Rows (plants: type · status · units · MW); Footer.
- **Above the fold:** at 390, header, pills, title, the definition line, Filters, the first 3 rows. At 1440, header through about 8 rows.
- **Key facts and sources:** Category name and definition (Category model); Count; For Plants and sites: type, status, units, operating MW.
- **Links in:** Homepage cards; Type chips on profiles; Crumbs on profiles; Search engines (title: e.g. "Uranium, nuclear fuel and materials suppliers in the US"). **Links out:** Profiles; Other categories (pills).
- **Cut:** Default sort A to Z: switch to Most connected; A missing definition line: add it.
- **Spec:** #263

### Company profile (`/companies/terrapower`)

Everything sourced about one company, and who it deals with. This is the shared frame; the key facts and sections that follow it depend on the category (next section). **For:** Someone checking a company: a journalist, an investor, a job seeker, a competitor.

- **Questions, in order:** 1. What does it do? (one line) 2. What kind of company is it? 3. Who does it deal with, and how? (owns, operates, supplies, sells power to, funds) 4. Which plants and sites is it tied to? 5. For reactor developers: how far along is licensing? 6. Where's the proof?
- **Sections, top to bottom:** Header; Crumbs: Category / Name; Mark, name, one-line description with sources; Key facts: Type chips, Website, Also known as, Legal name, Role, Technology, Headquarters, Parent company, Licensing stage (developers); Connections map (#363); Deals and links (n); Plants and sites (n); Sources (n); Report a correction; Footer.
- **Above the fold:** at 390, header, crumbs, name, description, and the first rows of key facts (Type, Website). At 1440, name and description on the left; the whole key-facts panel on the right; the top of the map.
- **Key facts and sources:** Description: from a source, numbered; Type: the company's categories (chips); Role, technology, HQ, parent: each with its source numbers; Licensing stage (reactor developers): NRC docket as the source; field defined by Data Quality; Deals and links: the five verbs, signed facts only.
- **Links in:** Lists, categories, search; Other profiles' deals and maps; Plant pages' Companies. **Links out:** Partners' profiles; Plants; Sources (external); Report a correction.
- **Cut:** The role tag row under the name: it repeats the Role fact and the Type chip; "Not verified yet" as a section heading: fold it into one muted line.
- **Spec:** #363, #369

### Company profile: one layout per category

Every company page shares one frame. Its first key facts and its sections follow its category, most important first (Tosin, 18 Oct). Each category has a board on the canvas, with 390 and 1440 wireframes.

- **Shared by every company:** crumbs; mark, name and the one-line summary with its sources; Type chips; the always-on key facts (Website, Headquarters, Parent company, Also known as, Legal name) after the category's own; the connections map (#363); Sources; Report a correction.
- **Varies by category:** the first 2 to 3 key facts; the sections after the map, and their order; each section's table columns.
- **Empty states, only what's sourced:**
  - A key fact with no source is left out: no row, never "unknown".
  - A section with nothing sourced is left out.
  - The exception is the category's first section. It stays, with one muted line ("No sourced projects yet.") and a Report a correction link, so the page still answers its main question.
  - Never infer one fact from another.
- **A company in several categories:**
  - Its first category (the one in its crumbs) sets the layout.
  - Its other categories' sections follow, once each, in their own order.
  - The key facts add each other category's first fact. Amazon: Nuclear power deals, Contracted MW, then Companies funded.
- **Plants and sites** isn't a company category; it has the plant profile. Isotopes and coolant sit inside Fuel and materials.

| Category | First key facts | Sections after the map, in order | Sources for its facts |
|---|---|---|---|
| Developers | Technology, Licensing stage, First project | Projects and sites; Licensing; Funding; Power deals; Suppliers | Technology: the reactor design and type (e.g. sodium-cooled fast reactor); Licensing stage: from the NRC docket (Data Quality defines the field); First project: the earliest site with a sourced stage; Funding and deals: signed facts only; MOUs are Notes (#363) |
| Power plant owners and operators | Plants operated, Plants owned, Operating capacity | Plants; Units by status; Power deals; Suppliers and services | Plants operated and owned: from the operates and owns links (shares from the source); Operating capacity: operating units only (PM, 16 Oct); Units by status: counts from the units table |
| Fuel and materials | What it makes, Facilities, Capacity | Facilities; Who it supplies; Funding and awards | What it makes: from its roles and facility types; Capacity: as the source states it, with its unit (e.g. SWU a year), never converted; Customers: from supplies links |
| Components and manufacturing | What it makes, Customers, Facilities | Who it supplies; Facilities | What it makes: from its roles and its supplies links' details; Customers: from supplies links |
| Services and engineering | Services, Clients, Plants served | Clients and contracts; Plants served | Services: from its roles (reactor services, regulatory consultant) and contract details; Clients and plants: from supplies links, dated |
| Waste and decommissioning | Services, Sites, Plants being decommissioned | Sites and projects; Clients | Sites: from its links to facilities (decommissioning status from the site); Clients: from supplies links |
| Power buyers | Nuclear power deals, Contracted MW, Sellers | Power deals; Investments (when it also invests) | Deals: signed only; early-stage ones are Notes with their stage (#363); Contracted MW: the sum of sourced amounts, labelled "sourced deals"; left out if any amount is missing |
| Investors | Companies funded, Focus, Total disclosed | Investments; Invests alongside | Investments: from invests_in and funds links; Total disclosed: the sum of disclosed amounts only, labelled so; Focus: from the funded companies' technologies |
| Government and research | Kind, Programs, Awards given | Awards and funding given; Programs; Labs and research sites; Research partners | Awards: from funds links; amounts from USAspending or the award page; Labs and sites: from its facilities (research reactors, test sites) |

### Plant profile (`/plants/plant-vogtle`)

What a plant or site is, whether it runs, and who owns and operates it. **For:** Someone looking up a plant: a reporter, a local resident, an analyst, a buyer of power.

- **Questions, in order:** 1. What is it, and is it running? 2. Where is it? 3. Who owns it, who operates it, and are they the same company? 4. How big is it? (units, operating capacity) 5. Which reactor type and developer? 6. Who buys its power? 7. Where's the proof?
- **Sections, top to bottom:** Header; Crumbs: Plants and sites / Name; Site ring, name, the ownership sentence; Type chip (with site icon) + status; Key facts: Type, Status, Location, Owners, Operator, Reactor developer, Reactor type, Capacity; Connections map (#363); Companies (n); Units (table; cards on phones); Sources (n); Report a correction; Footer.
- **Above the fold:** at 390, header, crumbs, name, the ownership sentence, the type chip, the first key facts (Type, Status). At 1440, name, ownership sentence and chips on the left; all key facts on the right.
- **Key facts and sources:** The ownership sentence (Founder): "Owned by Georgia Power, Oglethorpe Power, MEAG Power and Dalton Utilities. Operated by Southern Nuclear, a different company." or "Owned and operated by Constellation." From the owns and operates links; only signed, sourced ones. With only the operator sourced, it reads "Operated by Constellation." on its own, never "owner unknown" or an inferred owner (see the rule above); Status and type: the site's own, once sourced; Capacity: operating units only (PM, 16 Oct); Reactor type: from the units when they agree.
- **Links in:** Plants and sites list; Company profiles; Search (units land on their row). **Links out:** Owner and operator profiles; Units' NRC dockets; Sources.
- **Cut:** Leaving the operator out of key facts when it's known (Calvert Cliffs lists Operator but no Owners); "Not verified yet" as a heading.
- **Spec:** #281, #363, Founder note 18 Oct

### Unit (`/plants/plant-vogtle#vogtle-3`)

One reactor's facts. A row on its plant's page, not a page of its own. **For:** Someone who searched a unit name ("Vogtle 3") or follows an NRC docket.

- **Questions, in order:** 1. What kind of reactor, and how big? 2. Is it operating? 3. What's its NRC docket?
- **Sections, top to bottom:** Its plant page, scrolled to the Units table; The unit's row highlighted (card on phones): Reactor type, Capacity, Status, NRC docket, Sources.
- **Above the fold:** at 390, the highlighted unit card, with the plant's name pinned above. At 1440, the Units table with the row highlighted.
- **Key facts and sources:** Reactor type, capacity, status: per unit, sourced; NRC docket: links to the NRC.
- **Links in:** Search results for a unit name; Connections that point to a unit. **Links out:** The NRC docket page; The plant's owners and operator.
- **Cut:** A standalone unit page: too thin, and it would split the plant's sources.
- **Spec:** #281

### Search (`Search box (every page) → /companies?q=…`)

Find a company, plant or site by name, alias or topic. **For:** Everyone; it's the main action.

- **Questions, in order:** 1. Is it here? 2. Is it a company or a plant? 3. If not, what's close?
- **Sections, top to bottom:** Instant results under the box: Companies, Plants and sites (5 each), All results ›; Results page: title "Results for …" + count; Filters; Companies; Plants and sites; No results: 3 suggestions + Report a missing company.
- **Above the fold:** at 390, the instant results; on the results page, the title, Filters and the first 4 results. At 1440, instant results in place; the results page through about 10 results.
- **Key facts and sources:** Matches name, aliases, legal name, plant and unit names; Plain group labels; no record types.
- **Links in:** The search box on every page; Homepage suggestions. **Links out:** Profiles (units land on their plant row); Corrections (missing company).
- **Cut:** Search inside admin-only fields.
- **Spec:** #245

### Technology page (`/companies?technology=smr`)

Everyone working on one technology (SMR, HALEU, fusion, molten salt). **For:** Someone who searched a technology or tapped a technology tag.

- **Questions, in order:** 1. Who's working on it? 2. What is it, in one line? 3. Which plants or sites use it?
- **Sections, top to bottom:** Header + pills; Title: technology name + count; One-line definition; Companies; Plants and sites using it; Footer.
- **Above the fold:** at 390, title, definition, the first 4 companies. At 1440, title, definition, about 8 companies.
- **Key facts and sources:** Definition: plain, one line (VOICE.md); Companies tagged with the technology; plants whose units use it.
- **Links in:** Technology tags on profiles; Homepage suggestions (HALEU, SMR); Search engines, only when it has 5+ results. **Links out:** Profiles; The full list with the filter.
- **Cut:** Indexing a technology page with fewer than 5 results (noindex).
- **Spec:** new, confirmed by Tosin on 18 Oct

### The data (`/data (coming)`)

Download the whole dataset and cite it. **For:** Researchers, journalists, analysts; anyone who wants to reuse or cite the data.

- **Questions, in order:** 1. What's in it? 2. How fresh is it? 3. How do I cite it? (DOI) 4. Can I reuse it? (licence) 5. How is it checked?
- **Sections, top to bottom:** Title + one-line summary (records, links, sources, last updated); Download: CSV and JSON, with size and date; Cite this: DOI + citation text + Copy; What's inside: tables and fields; How it's made: sources, Joy and Aminah's checks, corrections; Versions and changes; Licence.
- **Above the fold:** at 390, title, summary, Download, the top of Cite this. At 1440, title through Cite this.
- **Key facts and sources:** Counts and last updated: from the snapshot; DOI: from the deposit (Founder memo); Licence: to be chosen.
- **Links in:** Footer; Profiles' Sources ("Get the whole dataset"); Papers and articles that cite the DOI. **Links out:** Downloads; DOI page; Corrections.
- **Cut:** Any form or sign-up before download.
- **Spec:** #185, Founder memo

### Report a correction (`/corrections/new`)

Tell us something is wrong or missing. **For:** A visitor who spotted an error; often someone from the company itself.

- **Questions, in order:** 1. What am I correcting? 2. What should I write? 3. What happens next?
- **Sections, top to bottom:** Title; About: the record or fact it came from; What should change? (textarea); Email (optional) + why we ask; Send; Sent page: what happens next.
- **Above the fold:** at 390, everything to Send. At 1440, the whole form.
- **Key facts and sources:** The record and fact are filled in from the link that opened it.
- **Links in:** Report a correction on every profile and fact; No results in search. **Links out:** Back to the record.
- **Cut:** Required email; Captcha (the hidden honeypot stays).
- **Spec:** #103

### Admin: Today (`/admin/checks`)

The admin's daily plan: four steps, then done. **For:** The admin, in short bursts, often on a phone.

- **Questions, in order:** 1. What do I need to do today? 2. How long will it take? 3. What will my click do? 4. Am I done?
- **Sections, top to bottom:** Greeting + 4 steps · minutes + who are Joy and Aminah; 1 Crawled and checked by Joy; 2 Aminah's review (paste); 3 Review and accept (opens the list); 4 Left for you; You're done for today.
- **Above the fold:** at 390, the greeting and all four steps. At 1440, the whole plan.
- **Key facts and sources:** Crawl run counts; Joy's and Aminah's verdicts per fact; Gates still run behind every click.
- **Links in:** Admin nav: Today (count). **Links out:** Fact pages; Correction requests; Sources.
- **Cut:** Claim, verifier, candidate, S1 in the interface.
- **Spec:** #373

## Categories

Home and the directory show the nine buckets of companies (docs/DATA.md section 4, #281) plus Plants and sites, in visitors' words (see `VOICE.md`). A bucket is presentation only: `Bucket` computes it from published, sourced roles and links, and nothing is stored. A company appears in every bucket its facts put it in; a bucket with no companies is hidden from the pills, the home boxes and the sitemap. Slugs never change once launched: a bucket that took over an older category keeps its slug.

| On screen | Slug | What it selects | Order |
|---|---|---|---|
| Developers | `reactor-developers` | roles `reactor_vendor` or `project_developer` (designs reactors or develops new nuclear plants) | 1 |
| Fuel and materials | `fuel` | roles `fuel`, `coolant` and their children, `isotopes` | 2 |
| Components and manufacturing | `components` | role `components` | 3 |
| Waste and decommissioning | `waste-decommissioning` | role `waste_decommissioning` | 4 |
| Utilities and operators | `utilities` | roles `utility` or `operator`, or a current owns or operates link to an operating power reactor | 5 |
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
