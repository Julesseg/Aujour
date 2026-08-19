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
placeholder, location suggestions from photo metadata, theme packs,
monetization design, macOS.
