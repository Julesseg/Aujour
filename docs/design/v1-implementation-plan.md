# Aujour v1 — Implementation plan

Sequencing for the scope fixed in `v1-decisions.md`. Architecture follows the
repo's standing rule: all behavior in `Core/` (SwiftPM, `swift test` on any
platform), thin SwiftUI in `App/`, XCUITest + CI as the canonical UI gate.

## Architecture: what lives where

**`AujourCore` (pure, Linux-testable — the bulk of the domain):**

- `JournalDay` — date identity + Rollover Hour resolution ("what day is it
  at this wall-clock instant").
- `PathTemplate` — Moment-token subset: render(date) → relative path, and
  inverse match(path) → date (regex built from the template). Also the
  Attachment Path Template (same engine, folder-only).
- `ContentTemplate` — placeholder parse/render; core placeholders resolved
  at spawn; data placeholders resolved via injected providers; interactive
  placeholders passed through as literal text (the editor owns them).
- `MigrationPlanner` — pure function: (existing entry paths, old template,
  new template) → move plan + collision list. No I/O.
- `ConflictPolicy` — pure decisions for divergence: which version keeps the
  Entry path, parked-file naming (`_1`, `_2`, …).
- `JournalStore` protocol — the file-system seam (list, read, write, move).
  Core ships an in-memory fake for tests; the real implementation lives in
  the App layer (security-scoped bookmarks, NSFileCoordinator are
  Apple-only).
- `SearchIndex` — tokenize/query over entry text; serializable, rebuildable
  cache per ADR 0001.
- `EntryMarkdown` — block/inline structure used by the editor styling pass.
  Hand-rolled rather than backed by apple/swift-markdown, as this plan first
  said, for two reasons found while building M3(a). swift-markdown gives an
  AST of a *whole document*, so every keystroke would cost a full reparse —
  and styling while typing is exactly the case that cannot afford one. And a
  styled *source* editor needs the delimiters themselves — which two
  characters made a word bold — where an AST is built to discard them. So
  the model reads one line at a time and points at every character, which is
  what lets the editor restyle a paragraph and leave the rest of the day
  alone. It also keeps Core dependency-free.
- `JournalSettings` — typed settings model + which keys are journal-shaping
  (KVS-synced) vs device-local; KVS itself is injected.

**`App/Aujour` (SwiftUI + platform frameworks):**

- Live-preview editor (`UITextView` over a custom `NSTextStorage`), accessory
  row, placeholder widgets (NSTextAttachment view providers). M3(a) shipped on
  TextKit **1**, not TextKit 2 as this plan first said: a text-storage subclass
  is the seam that sees every change to the text and can answer it one
  paragraph at a time, and it is what selects the TextKit 1 stack. This is the
  schedule risk below being taken rather than fought — stage (a) is the
  shippable fallback, and it is shipped on the path there was no way to verify
  from a Linux session. Revisit when stage (b) needs cursor-aware hiding.
- FileJournalStore: bookmarks, NSFileCoordinator/NSFilePresenter, autosave
  loop, external-change reload, iCloud conflict (NSFileVersion) handling.
- Calendar/history navigation, onboarding, settings screens.
- PhotoKit suggestions panel + system photo picker; EventKit providers for
  {{events}}/{{reminders}}; CoreLocation + place picker for {{location}}.
- Local notification scheduling; export/share; theming.

## Milestones

Each milestone leaves the app shippable-quality for what it contains.

- **M0 — Domain foundations (Core only).** JournalDay + rollover,
  PathTemplate render/match, ContentTemplate with core placeholders,
  JournalSettings, JournalStore protocol + fake. Exhaustive unit tests —
  this is the fast loop everything else leans on.
- **M1 — Walking skeleton.** Default iCloud folder, today view with a
  *plain* text editor, lazy spawn from template, debounced autosave,
  calendar with entry indicators, past-day backfill, future days locked.
  End-to-end journaling works, ugly but true.
- **M2 — Vault coexistence.** Custom folder picking + bookmarks, file
  coordination, live reload when clean, divergence parking, template-change
  migration flow (skippable, collision prompts, `_1` parking). This is the
  Obsidian promise, done before the pretty editor so it hardens early.
- **M3 — The editor rock.** Progressive: (a) styled source mode — headings,
  bold, lists rendered with syntax visible; (b) syntax hiding at cursor
  (true live preview); (c) checkboxes + image embeds inline; (d) accessory
  row. Each stage is shippable if the next proves slow — the fallback story
  for the schedule risk.
- **M4 — Attachments & photos.** Attachment pipeline (naming, HEIC→JPEG),
  manual insert via system picker, embed-syntax setting, photo suggestions
  panel (library permission, PhotoKit day query, thumbnails).
- **M5 — Placeholders.** {{events}} + {{reminders}} providers and formatting
  settings; interactive-placeholder widget machinery; {{mood}}; {{location}}
  with place picker.
- **M6 — Product shell.** Full-text search, export/share, daily reminder,
  theming (light/dark/auto, accents, fonts), onboarding, empty states, iPad
  layout pass, App Store assets.

M4 and M5 are independent of each other (both depend on M3's embed/widget
support); they can proceed in parallel via the agent-dispatch workflow.

## Issue breakdown (for `ready-for-agent` dispatch)

One issue ≈ one agent session. `Blocked by` chains mirror the milestone DAG.

M0: (1) JournalDay + Rollover Hour; (2) PathTemplate render + inverse match;
(3) ContentTemplate + core placeholders; (4) JournalSettings + KVS seam;
(5) JournalStore protocol + in-memory fake.

M1: (6) FileJournalStore for the default folder; (7) today view + plain
editor + lazy spawn + autosave; (8) calendar view + backfill + locked
future.

M2: (9) custom folder picker + bookmark persistence; (10) file coordination
+ external reload; (11) divergence parking; (12) MigrationPlanner (Core) +
migration UI flow.

M3: (13) styled source mode; (14) cursor-aware syntax hiding; (15)
checkboxes + inline image embeds; (16) accessory row.

M4: (17) attachment pipeline + manual insert + embed-syntax setting;
(18) photo suggestions panel.

M5: (19) data-placeholder provider seam + {{events}}/{{reminders}};
(20) interactive-placeholder widget machinery; (21) {{mood}}; (22)
{{location}}.

M6: (23) SearchIndex + search UI; (24) export/share; (25) daily reminder;
(26) theming; (27) onboarding + empty states; (28) iPad layout audit.

## Testing strategy

- Core: Swift Testing, aiming at near-total coverage of templates, rollover,
  migration planning, conflict policy — the domain edges the grilling
  surfaced (collisions, 1 AM, template change) each get a named test.
- XCUITest (CI-gated): spawn-today, edit-persists-across-relaunch, backfill
  via calendar, migration prompt flow, photo insert.
- Manual on-device passes for what simulators can't prove: iCloud
  divergence, Obsidian round-tripping in a real vault, Files-app picking.

## Known risks

- **TextKit 2 live preview** is the schedule risk; mitigated by M3's
  shippable stages (styled source mode is an acceptable v1 fallback).
- **Moment-token inverse matching** is ambiguous for exotic templates;
  v1 restricts path templates to unambiguous (zero-padded numeric + literal)
  tokens and documents the subset.
- **iCloud coordination** edge cases only reproduce on hardware; M2 gets
  dedicated on-device soak time before M3 begins.
