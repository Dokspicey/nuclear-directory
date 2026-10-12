# Nuclear Directory voice guide

Read this before writing any text that appears on the site: page copy, headings, labels, buttons, empty states, errors, organization descriptions. `DESIGN.md` covers how things look; this file covers what they say.

Two project skills apply it:

- `ux-writing` (`.claude/skills/ux-writing`) for interface text: buttons, labels, filters, empty states, errors, forms.
- `humanizer` (`.claude/skills/humanizer`) as a last pass on any prose, to remove the habits that make text read as machine-written.

Where those skills and this guide disagree, this guide wins. The overrides are listed at the end.

## Who we write for

Investors, startup business development teams, analysts, journalists, policy staff and students. They know the industry or are learning it on purpose. They come to look something up, check it and leave. They do not need to be persuaded; they need to trust what they read.

## The register

Write like a reference work: Wikipedia, a good trade publication's data desk, an NRC fact sheet written by someone who cares about readers. The site states facts and shows where they came from. It does not sell.

- Say what a thing is. "Kairos Power develops fluoride salt-cooled reactors." Not "Kairos Power is pioneering the future of clean energy."
- Use the industry's own words exactly: HALEU, SMR, offtake agreement, construction permit, docket number. Don't explain them inline; the glossary does that.
- Prefer numbers with units and dates to adjectives. "1,117 MWe, in service since 2024" beats "a major new unit".
- Third person for organizations and facilities. Second person ("you") only in instructions, forms and errors.
- Sentence case everywhere. Uppercase only where the design system sets it (Anton display type, `label` style).
- No exclamation marks, no emoji.

## Words visitors use

The database says "organization", "facility" and "role". Visitors don't. On screen, use their words:

| In the data | On screen |
|---|---|
| organization | company (or the specific kind: fuel supplier, power buyer) |
| facility | power plant, or plant and site when it includes test reactors and fuel plants |
| reactor_vendor | reactor developer |
| reactor_services | repair and services |
| data center offtaker | power buyer |
| offtake agreement | power deal in navigation and suggestions; offtake agreement in the fact itself |

Name categories by what's in them, and show two or three real examples so people recognize them.

## Headings name what is on the page

A heading tells the reader what the section holds. It is never a slogan.

| Don't | Do |
|---|---|
| Trust is the product | How we check facts |
| The US nuclear industry, mapped | Nuclear Directory |
| Browse by role | Organizations by role |
| Recently verified | Recently added and changed |

## Page intros are one or two plain sentences

Say what the page is and what it covers. No tagline above the title, no promise below it.

> A directory of the organizations and facilities in the US nuclear industry, and the agreements between them. Each fact links to the public document it came from.

## Prose has hierarchy

Pages of running text (privacy, the crawler page, the disclaimer) are read in pieces, so every block puts its point first. Tosin's words: "the main thing, the text, the subtext, the reasons."

1. **The main thing.** The point, stated as a plain sentence. In a short section the heading can carry it ("It isn't advice"). In a longer one, the heading names the topic ("Analytics") and a bold first line states the point ("We count how the site is used, without cookies").
2. **The text.** One or two short sentences that explain it.
3. **The subtext.** Details, only if needed, as a short list in smaller type.
4. **The reasons.** Why, last and brief. Leave it out if the reason is obvious.

One point per block. If a paragraph covers two things (what we record and where the script loads from), split it into two blocks, each with its own lead line.

| Don't | Do |
|---|---|
| A paragraph that opens with the tool, then lists what it records, then how it's stored, then where it loads from. | **We count how the site is used, without cookies.** Then what's recorded, then the details as a list. Where the scripts load from is its own block. |

## Facts and sources

- Every factual sentence on a profile carries a source chip. If we can't source it, we don't publish it.
- State the relationship exactly, using the fixed verbs: *supplies*, *invests in*, *offtakes from*, *owns*, *operates*, *vendor for*. Never "is associated with" or "partners with" when the source says something more specific.
- Give dates as `2026-10-09` in data and tables, "October 2024" or "Oct 9, 2026" in sentences.
- Say what we don't know plainly: "Founding date not published." Don't guess and don't apologize.
- Counts and "as of" dates are data. Show them in mono, in a colophon line, not as big-number tiles.

## Interface text

- Buttons: verb plus object, sentence case. "Suggest an organization", "Report a correction", "Export CSV", "Clear filters".
- Filters and labels: plain nouns. "Role", "Technology", "State".
- Empty states say what happened and what to do next, flatly:
  > No organizations match these filters. Clear filters
  > Nothing matches "molten salt pump". Suggest an organization
- Errors say what failed and how to fix it: "Enter a link to a public source, starting with https://".
- Confirmations are short and past tense: "Correction sent. We'll review it against the source."

## Words and habits to avoid

- Slogans and aphorisms: "Trust is the product", "X, mapped", "Power starts here".
- Promotional words: pioneering, leading, cutting-edge, revolutionary, robust, seamless, unlock, empower, landscape, ecosystem (unless it means a biological one).
- Significance padding: "plays a key role", "marks a pivotal moment", "reflects a broader shift".
- Contrasts against something nobody said: "not just a directory, but…".
- Lists of three that exist for rhythm.
- Em and en dashes in prose. Use a comma, colon, period or parentheses.
- Sections that describe themselves: "Below you'll find…", "This page shows…".

## Overrides for the skills

The `ux-writing` skill was written for consumer apps. For this site:

- Ignore "focus on user benefits, not features". Describe what the data is.
- Ignore "hopeful, encouraging" empty states and "celebrate early wins". Keep empty states neutral.
- Reading level: write for professionals (its 9th–10th grade band), and keep industry terms.

The `humanizer` skill applies as written. Our text is reference text, so keep it "neutral and plain", and never add a fact, number or date that isn't in a source.

## Sources for this guide

- GOV.UK style guide and content design guidance: plain language, front-loading, no marketing tone.
- Wikipedia Manual of Style, "Words to watch", and "Signs of AI writing".
- Microsoft Writing Style Guide, for UI text conventions.
