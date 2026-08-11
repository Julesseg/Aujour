# 0002 — Only the current Path Template defines Entries; changes offer a skippable migration

Date: 2026-08-11
Status: accepted

## Context

A file becomes an Entry by matching the Path Template — but users change
templates, and in a shared Obsidian vault the new template's paths may already
be occupied by notes Obsidian created. Alternatives considered: matching
against a remembered history of past templates (no file moves, but Entry
identity becomes multi-rule), and liberal date-detection (swallows vault notes
that were never journal entries).

## Decision

An Entry is a .md file under the Journal Root whose relative path exactly
matches the *current* Path Template rendered for some date. Nothing else is
an Entry.

Changing the Path Template offers to migrate (move/rename) all existing
Entries to the new structure. The migration is skippable: declining leaves
old files on disk untouched, where they cease to be Entries (invisible
in-app, never deleted).

If a migration target already exists (two files claiming the same day), the
user is prompted for confirmation and the migrating file is parked next to
the target as `{filename}_1.md`, leaving the existing file in place as the
day's Entry. The parked file is deliberately *adjacent* so the user notices
it in Obsidian or Files and can merge by hand — Aujour never auto-merges or
rewrites notes it did not create.

## Consequences

- Entry identity stays a single clean rule; no template-history bookkeeping.
- A skipped migration orphans journal history from the app's point of view
  (files remain on disk per ADR 0001). Aujour deliberately does not track or
  surface orphaned old-structure files afterwards — the user manages them in
  Files or Obsidian if they care.
- Renaming files can break Obsidian [[links]] to daily notes; the migration
  prompt must say so.
- `_1` suffixed files are never Entries; they are parked content awaiting
  manual merge.
