# Aujour v1 — UI design prompt

A self-contained brief for a design tool (Claude design / Figma). Derived from
issue #4 (v1 umbrella spec), `CONTEXT.md`, and `docs/design/v1-decisions.md`.
Copy everything below the rule.

---

Design the complete UI for **Aujour**, a free on-device iPhone + iPad
journaling app. Produce every screen, state, and component listed below as a
cohesive design system.

## The product in one paragraph

Aujour is a once-a-day journaling app whose entire data model is a folder of
plain markdown files — one file per day, in a folder the user owns (its own
iCloud Drive folder by default, or any folder they pick, typically inside an
Obsidian vault). It gives the warm, polished daily-writing surface that
dedicated journaling apps have, while leaving the journal as plain files that
outlive the app. Everything is on-device: no accounts, no servers, no paywall.
Deleting the app loses nothing.

## Design language: iOS 26 Liquid Glass, done properly

- Target the current iOS system design language (Liquid Glass). Navigation and
  controls float in translucent glass layers **above** an opaque content
  layer; they refract and dynamically tint from the content scrolling beneath,
  and specular highlights track the light.
- **Never stack glass on glass.** One glass layer above content. Group related
  floating controls into a single glass container so they morph and merge
  rather than sitting as separate lozenges.
- Text — the journal itself — lives on the opaque content layer and is never
  put behind glass. Legibility of the user's words outranks every effect.
- Use concentric corner radii: nested elements share a center with the
  container's curve. Respect the device's screen corner radius for
  edge-hugging containers.
- Controls are capsule-first: floating capsule toolbars, capsule buttons,
  capsule date pills.
- Motion is fluid and interruptible — glass elements stretch, merge, and
  settle with spring physics; sheets morph out of the control that summoned
  them rather than cross-fading in.
- Full light / dark / auto. Design both from the start; glass tints and
  highlight treatments differ, not just the color values.
- Accent colors: a curated set (about 6–8) — a warm default plus muted,
  paper-adjacent alternatives. Accent tints the glass and the interactive
  affordances, never body text.
- Typography: system SF for chrome; the editor offers a few hand-picked
  reading fonts (a serif, a humanist sans, a mono) with a size control.
  Editor line length, leading, and margins should read like a well-set page.
- The overall feeling: warm, paper-like, unhurried, quiet. Restraint over
  decoration. Zero gamification — no streaks, no badges, no confetti.

## Navigation model (the spine — get this right first)

The app is single-surface. **Today's entry is the root screen**; you land in
your writing, not in a list.

- **Header date pill** (glass, centered at the top): shows the current Journal
  Day, e.g. "Tuesday, 13 August". Tap or drag it down and it **expands
  downward into a week strip, then a full month grid** — a continuous,
  interruptible drag, not a modal push. Drag back up (or pick a day) and it
  collapses to the pill. This is the primary calendar navigation and it must
  feel like the single best gesture in the app.
- **Horizontal swipe** between adjacent days in the editor; matched to the
  calendar selection.
- A **"Today" affordance** appears in the header whenever you are not on
  today; tapping it returns.
- **Floating glass toolbar** — a single merged container, bottom or top-
  trailing: search, share/export, settings. It recedes (fades and contracts)
  while typing and returns on scroll or tap-away.
- Settings, search, share, and the photo picker are **sheets** that morph from
  their originating control. Nothing that isn't writing gets a full push.

Design both **iPhone** (compact) and **iPad** layouts. On iPad, the calendar
lives permanently in a sidebar next to the entry; the editor gets a comfortable
measure with generous margins rather than stretching edge to edge; support
Split View and external-keyboard use.

## Screens and states to design

### 1. Onboarding (3 short screens, glass sheets over a soft backdrop)
1. **Welcome** — one sentence on what Aujour is: your journal, as plain files
   you own. Warm, no feature grid.
2. **Where your journal lives** — the default folder is preselected and works
   with zero setup; a secondary path lets Obsidian users pick a folder in the
   Files app. Explain in one line, don't lecture.
3. **A gentle reminder** — offers a daily reminder time with a compact time
   picker; skipping is a first-class, equally-weighted choice.

### 2. Today / Entry editor — the heart of the app
- Header date pill (as above), the writing surface, nothing else competing.
- **Live-preview markdown**: formatting renders in place (headings, bold,
  italic, lists, quotes, code, checkboxes, image embeds); raw syntax appears
  only on the line the cursor is on, then hides again when the cursor leaves.
  Show the *same* passage in both rendered and cursor-active states.
- Inline **checkboxes** (tappable) and inline **image embeds** (rounded,
  full-width-in-measure, tappable to view).
- **Empty / freshly spawned state**: the entry pre-filled from the user's
  content template with placeholders resolved, plus an unobtrusive invitation
  to start writing. Nothing is written to disk until the first keystroke —
  the design must not imply a file already exists.
- **Backfill state**: a past day opened for the first time, spawned from the
  template with that day's date; subtly marked as a past day being written now.
- **Locked future day**: shown, readable, and clearly not writable — a calm,
  non-error treatment ("this day hasn't arrived yet"), never an alert.
- **Saving is silent.** No save button, no spinner, no "saved" toast. At most a
  whisper-quiet state indicator.
- **External-change reload**: when Obsidian edited the same file, the entry
  quietly refreshes; design the near-invisible acknowledgment.
- **Parked File notice**: when two devices genuinely diverged, an inline glass
  banner above the entry — "Another version of this day was kept as
  2026-08-13_1.md" — with a tap to view the parked version side by side. Calm
  and reassuring: nothing was lost. Never an error color.

### 3. Keyboard accessory row
A single merged glass row above the keyboard: heading level, bold, italic,
bullet list, numbered list, checkbox, indent, outdent, insert photo. Horizontal
scroll for overflow. One-tap targets, generous hit areas, obvious pressed
states. Design the row in light and dark, over both keyboard types.

### 4. Photo suggestions panel
A shallow glass tray that rises above the accessory row while editing, showing
that day's photos as a horizontally scrolling thumbnail strip; tap to insert at
the cursor. Include: permission-not-yet-granted state, limited-access state,
and no-photos-that-day state. Also design the entry point to the full system
photo picker.

### 5. Interactive placeholder widgets (inline, inside the text)
These are literal `{{mood}}` / `{{location}}` text in the file until answered,
rendered as inline widgets in the editor:
- **`{{mood}}`** — an inline 1–5 rating control that, once tapped, collapses in
  place into plain text ("Today's mood: 4/5"). Design the widget, the tap
  moment, and the collapsed result.
- **`{{location}}`** — an inline place chip pre-filled with the current place,
  tappable to open a compact place picker sheet; collapses to plain text.
- **Unanswered placeholder** — how a `{{name}}` widget looks sitting quietly in
  a paragraph without breaking the reading rhythm.

### 6. Calendar / history
- The expanded month grid from the header pill: days with entries carry a
  quiet indicator (a dot or a subtle filled ground — not a badge), today is
  distinct, future days are visibly locked, the selected day is unmistakable.
- Vertical scroll spans months continuously; month labels stick.
- Selecting a day collapses the calendar and lands you in that entry.
- On iPad this is the persistent sidebar; design it as both an overlay grid and
  a sidebar.

### 7. Search
Full-text across all entries. A search field in a glass sheet, results grouped
by day with the matched line as a snippet and the term highlighted; recent
searches when empty; a warm no-results state.

### 8. Share / export
The share sheet entry point plus a small format choice — PDF or plain text —
and a PDF preview showing how an entry sets on a page (typography carried
over from the editor).

### 9. Settings
Root list, grouped, with these sub-screens:
- **Journal folder** — where the journal lives; current folder shown clearly;
  changing it opens the Files picker. Explain consequences in one calm line.
- **Path Template** — a text field with live preview: "Today's entry would be
  `2026/08/2026-08-13.md`". Inline validation for unsupported tokens, phrased
  as guidance rather than failure.
- **Content Template** — a multi-line editor with a placeholder reference the
  user can tap to insert; live preview of a spawned entry.
- **Attachments** — attachment path template (same live-preview treatment) and
  the embed-syntax toggle (standard markdown vs. Obsidian wiki style) with a
  one-line example of each.
- **Rollover Hour** — a time picker with a plain-language explanation: "Writing
  at 1 AM still counts as yesterday."
- **Calendar events** — formatting options for the `{{events}}` /
  `{{reminders}}` placeholders, plus the permission state.
- **Appearance** — light/dark/auto, accent swatches, editor font choices, text
  size, all previewed live on a sample paragraph.
- **Daily reminder** — on/off and time; a line noting it is skipped on days
  already written.
- **About** — free, on-device, no accounts; where the files are.

### 10. Template migration flow
Triggered when the Path Template changes:
1. **Prompt** — "Move your 142 existing entries to the new layout?" with Move,
   Skip, and Cancel. Skipping is safe and clearly labeled as such.
2. **Plan review** — a scrollable before → after list of paths.
3. **Collision prompt** — a file already exists at a target path; show both,
   explain that the incoming one will be parked adjacently as `{filename}_1.md`,
   and make clear nothing is ever overwritten.
4. **Progress** and **summary** — moved, parked, skipped counts.
Tone throughout: this is careful, reversible-feeling, never alarming.

### 11. Permissions & system moments
Pre-permission explainer cards, in Aujour's voice, before each system prompt:
photos, calendar/reminders, location, notifications. Each says what it buys the
user in one sentence, and each is refusable without breaking the app.

### 12. Empty and edge states
First launch with no entries; a month with no entries; search with no results;
photos with no library access; the journal folder temporarily unavailable
(iCloud still downloading). All warm, all short, none of them alarming.

## Deliverables

1. Every screen above, in **light and dark**, at iPhone and iPad sizes.
2. The key **flows** as sequences: land → write; pill → month grid → past day;
   template change → migration; insert a photo; answer a `{{mood}}` widget.
3. A **component library**: glass toolbar container, header date pill, calendar
   cell (all states), accessory-row button, inline placeholder widgets, inline
   banner, list rows, sheet chrome, buttons, text fields with live preview.
4. **Design tokens**: color (light/dark × accent set), typography scale
   (chrome + editor faces), spacing, corner-radius scale, elevation/glass
   material definitions, motion specs for the pill↔calendar expansion and the
   accessory-row reveal.
5. Annotations on the **calendar expansion gesture** and the **live-preview
   syntax reveal** — the two interactions the whole app is judged on.

## Out of scope

Streaks, stats, "On This Day", health/weather placeholders, prompt packs, theme
packs, paywall or purchase screens, macOS, and any account, login, or sync
settings UI — sync is the folder's job, not the app's.
