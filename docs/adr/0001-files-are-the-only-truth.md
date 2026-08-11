# 0001 — The markdown files are the only source of truth

Date: 2026-08-11
Status: accepted

## Context

Aujour stores journal entries as plain markdown files in a user-visible
folder, possibly inside an Obsidian vault that other software edits freely.
Features like favorites, moods, streaks, and search need *some* persistent
state, and the tempting default is a private app database alongside the files.

## Decision

The markdown files (plus any attachments in the Journal Root) are the single
source of truth for everything a user would grieve losing. App-private storage
is limited to settings: the folder bookmark, templates, theme, and
notification preferences. Any index Aujour keeps (search, calendar dots,
streaks) is a disposable cache, rebuildable at any time by scanning the
Journal Root.

Consequently, user-meaningful features must round-trip through the files —
e.g. per-entry metadata goes in YAML frontmatter — or they don't ship.

## Consequences

- Delete the app, keep the folder: nothing is lost.
- Edits made by Obsidian (or any other tool) are always legitimate; Aujour
  must reconcile by re-reading files, never by "restoring" from its own state.
- Feature designs are constrained: anything not representable in markdown/
  frontmatter needs a redesign or gets cut.
- Sync is delegated to the folder's own mechanism (iCloud Drive, Obsidian
  Sync, etc.); Aujour does not implement sync.
