# Aujour v1 — Product decision log

Outcome of the design grilling session on 2026-08-11/12. Vocabulary lives in
`CONTEXT.md`; foundational trade-offs have ADRs in `docs/adr/`. This file
records the remaining product decisions and the v1 line.

## Product

- **Audience:** App Store product from day one. Non-Obsidian users are
  first-class; real onboarding and empty states required.
- **Devices:** Universal iPhone + iPad at launch. macOS is out of scope.
- **Pricing:** Free at launch, no purchase code in v1. If monetized later,
  gate new premium features — never the journal or the files.
- **Privacy stance:** everything on-device; no servers, no accounts.

## Storage

- **Default:** entries go to Aujour's own iCloud Drive folder (visible in
  Files). Settings offer "Use a custom folder…" via the Files picker
  (security-scoped bookmark) — the Obsidian-vault path.
- **Truth model:** files are the only source of truth (ADR 0001). All
  indexes (search, calendar) are disposable caches rebuilt by scanning.
- **Sync:** delegated entirely to the folder's own mechanism (iCloud Drive,
  Obsidian Sync, …). Aujour implements no sync of content.

## Entry model

- **Identity:** one Entry per Journal Day; a file is an Entry iff its path
  matches the current Path Template (ADR 0002).
- **Rollover Hour:** setting, default midnight (= Obsidian behavior).
- **Default Path Template:** `YYYY/MM/YYYY-MM-DD`.
- **Template changes:** skippable migration; collisions prompt and park as
  `{filename}_1.md` (ADR 0002). After a skipped migration nothing is
  surfaced anywhere — orphaned files are the user's to manage.
- **File creation:** lazy — the rendered template appears in the editor, but
  nothing touches disk until the first user edit. "File exists" therefore
  means "journaled".
- **Backfill:** any past day can be opened and spawned from the calendar;
  future days are visible but locked.
- **External edits:** continuous debounced autosave (plus on background);
  live reload while the editor is clean. True divergence: newest version
  keeps the Entry path, older is parked as `{filename}_1.md` with an in-app
  notice. No words are ever silently discarded.

## Templates & placeholders

- **Path syntax:** Moment-format tokens, literals in `[brackets]`, `.md`
  auto-appended — Obsidian daily-notes formats paste over verbatim.
- **Content Template:** a markdown file the user picks from anywhere on the
  device and Aujour reads at spawn — Obsidian's "Template file location", so
  an existing daily-notes setup is pointed at rather than pasted in. Inside
  the journal folder it syncs as a path; elsewhere it is a per-device
  bookmark (ADR 0005). Obsidian core set ({{date}}, {{time}}, {{title}} with
  `:FORMAT`) plus Aujour placeholders (see CONTEXT.md taxonomy:
  core / data / interactive). Unknown placeholders render as empty in
  Aujour and stay harmless literals in Obsidian.
- **Settings home:** journal-shaping settings sync via iCloud KVS
  (ADR 0003); theme/fonts/notification time are device-local.

## Editor

- **Mode:** live-preview hybrid (Bear/Obsidian-style: formatting renders in
  place, syntax reveals at the cursor). Accepted as the single biggest
  engineering effort in the app.
- **Accessory row:** markdown bar above the keyboard — headings,
  bold/italic, lists, checkboxes, indent/outdent, photo insert.

## Attachments

- **Location:** Attachment Path Template, Moment-format, default
  `[attachments]/YYYY/MM`.
- **Embed syntax:** setting — standard markdown (default) or Obsidian
  wiki-style; Aujour renders both regardless.

## v1 scope

Ships: photo suggestions panel ("N photos from this day", library
permission), manual photo insert via system picker (no permission),
{{events}} + {{reminders}} data placeholders (EventKit), {{mood}} and
{{location}} interactive widgets, full-text search, export/share
(PDF/text via share sheet), one gentle daily reminder auto-skipped when
today's Entry exists (off until a time is chosen in onboarding), calendar
history view (core navigation), theming: light/dark/auto + curated accents
+ editor fonts with size control.

Roadmap (explicitly deferred): streaks & stats, On This Day,
{{workout}}/{{sleep}}/{{steps}} (Apple Health), {{weather}},
{{scale:Name}} generic rating widget, {{prompt}} packs, {{onthisday}}
placeholder, theme packs, monetization design, macOS.

Pulled forward into v1: location suggestions from photo metadata (#71). The
{{location}} widget could otherwise answer only "where is this device now",
which for a Backfilled day is the wrong question — a Monday written up on
Friday was offered Friday's street, one tap from being confirmed into the
file. The day's own photographs already know better, and the panel that offers
them was already reading the same day.

## Visual identity (grilling session 2026-08-24/25)

Source files live in `docs/design/identity/`. They set the aesthetic — paper
and ink, restrained translucency, Newsreader over a cream ground — and are
**not** a technical spec: where they contradict `CONTEXT.md` or Core, the
documented model wins, and what they omit is extrapolated from it.

- **Live Preview is not a restyle.** The design shows a cursored line swapping
  to monospace, which shrinks a heading from 24px serif to 17px mono on entry.
  `CONTEXT.md` says the opposite — a heading's hashes may be hidden precisely
  *because the line stays large*. Marks are revealed in place, at the styled
  size, tinted `--ink-3`. Nothing reflows under the caret.
- **Contrast floor** above the design files' tokens — ADR 0006.
- **Dynamic Type for chrome, the in-app control for the editor body.** The
  S/M/L/XL setting is a writing preference and governs the Entry only;
  settings rows, calendar and chrome scale with the system text size.
- **Accent is a Device Setting** and does not sync (ADR 0003's reasoning:
  nothing here shapes a file). Theming ships in its own ticket; until then the
  Appearance sheet has no accent row and the default is Driftwood `#7B6A52`.
  The third editor face is the system sans — Source Sans 3 is dropped rather
  than bundle a webfont for one settings row.
  That ticket was #31, and it landed on 2026-08-26: the sheet offers the
  identity's nine accents, each raised to the contrast floor (ADR 0006), and
  `CONTEXT.md` carries them under Device Settings. The "until then" above is
  therefore spent, and the accent row stays.
- **Settings speak prose, not the glossary.** "When the day turns", not
  "Rollover Hour". Attachment Path Template and embed syntax stay two rows,
  not one, and the sheet is split into "Your journal" (syncs) and "This
  device" so ADR 0003's boundary is visible.
- **Data placeholder formatting gets a screen**: a row per placeholder, each
  opening its `linePrefix` / `donePrefix` / `timeFormat` / `whenEmpty` fields,
  reusing the live-preview-with-guidance field the path template already uses.
  Done marker shown only for placeholders that have a done state.
  That ticket was #87, and it landed on 2026-09-01: the row shows the token as
  its value rather than its label, and each field's worked example is rendered
  over a made-up day rather than the user's own — a real day may hold nothing,
  which is exactly the day the empty text is for and the worst one to check the
  other three fields against.
- **No compare view for a Parked File.** The design's "Compare" label had no
  handler and no referent in the model; it becomes "Show in Files". Merging
  happens in the user's own editor — see `CONTEXT.md`, Parked File.
- **Migration has three states**: preview (prose count, collisions listed by
  the name they'd be parked under, Move/Skip), working (determinate — it
  touches every file), result. A partial outcome (`MigrationOutcome.leftBehind`)
  is reported in the inline banner's shape and in accent, never an error colour.
- **An unanswered placeholder is one chip over the whole token**, carrying its
  name and symbol, tapped to open the answering sheet — as `DrawnMarkdown.Chip`
  already does. A `:FORMAT` suffix does not change the chip. The design's five
  inline tappable mood dots become what the *sheet* shows: one interaction for
  every placeholder, and no per-placeholder hit-testing inside a drawn glyph.
  That shipped in #88, where the chip also moved onto the identity's own wash
  and lettering and the dots became the sheet's five marks.
- **The iPad layout is width-dependent, not device-dependent.** Below ~820pt
  of *window* width (so Slide Over, half-width Split View and a narrowed Stage
  Manager window all count), the iPhone presentation: the date pill with its
  drag-to-week-to-month gesture, which therefore ships on iPad too. At or above,
  `NavigationSplitView` with the month grid in the sidebar and the Entry at a
  ~65-character measure. Crossing the threshold keeps the selected day and
  resets the pill to closed, unanimated.
- **Onboarding is three sheets**: what this is (a folder of markdown files you
  own), where it lives (iCloud primary, "choose a folder…" for the vault case),
  when to nudge (skippable time picker). Photo permission is not among them —
  asking is a separate act, done before a day is opened.

- **The bar is one menu, not three icons.** The design draws search and
  settings as separate glyphs across the top, with sharing a third once the
  Entry screen has one. Shipped, that is three controls competing along the
  top edge with the one thing anybody opened the app to do, on the screen the
  identity spent its whole budget making a page of writing. So they are one
  `ellipsis` at the trailing end — search, send this day, settings — and the
  leading end is empty. The pill still names the day, which is the only thing
  up there that is about the day. The cost is real and is the reason it is
  written down: search is the second most-used thing in the app and is now one
  tap further away. Sending stays on whichever screen the day was opened from,
  so a day reached through search offers it as a button rather than a menu of
  one.

- **The pill takes the bar, and gives up a word at a time.** Following the
  menu decision above, the date pill moves up onto the bar's own row and the
  screen loses its navigation bar altogether — it was drawing an empty title
  over a pill that already names the day. That buys a bar's worth of height
  back for the writing, which is what the screen is for.
  It does not fit as-is. The pill carries a "Today" chip on any day that is not
  today, spells the year out on a day from another year, and follows Dynamic
  Type; measured, the ellipsis takes 92pt of an iPhone SE's 320 before the pill
  gets anything, and a day from a previous year wants 347pt of the 228 left.
  So two things change with it: the chip gives up its word for a glyph, worth
  52pt, and the day is said at the longest of four lengths that fits
  (`JournalDay.Length`) — the weekday's full name goes first, then the month's,
  then the weekday altogether. Today at the factory text size is still spelled
  out in full on the smallest phone; what steps down is a backfilled day, or a
  reader who has turned the text up. Nothing truncates.
  Prototyped on the `prototype/the-header` branch, which holds the five layouts
  that were measured and the contact sheets they were judged on.

Still undesigned and not extrapolated here: the iPad sidebar's own empty and
loading states, and `{{workout}}`-class placeholders that are roadmap anyway.
