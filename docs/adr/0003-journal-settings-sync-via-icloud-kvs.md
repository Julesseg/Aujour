# 0003 — Journal-shaping settings sync via iCloud key-value storage, not a config file in the vault

Date: 2026-08-11
Status: accepted

## Context

Aujour runs on iPhone and iPad against the same folder. If two devices
disagree on the Path Template, they write the same day to two different paths
and shred the one-Entry-per-day rule — so the journal-shaping settings (Path
Template, Content Template, Attachment Path Template, embed syntax, Rollover
Hour) must be consistent across devices. The obvious alternative was a
dotfile (e.g. `.aujour/config.json`) inside the Journal Root, which would
travel with the journal itself.

## Decision

Journal-shaping settings live in local app storage and sync across the user's
devices via iCloud key-value storage. Aujour writes no configuration files
into the Journal Root — the folder contains only Entries, Attachments, and
Parked Files. Device-scoped preferences (theme, fonts, notification time)
stay purely local. The Journal Root security-scoped bookmark is inherently
per-device: each device picks its folder once, but the settings that shape
what gets written there arrive synced.

## Consequences

- The vault stays free of app droppings; nothing to explain to Obsidian
  users or exclude from their sync/backup tooling.
- Consistency is scoped to one Apple ID. A vault shared between two people,
  or synced to a device on another account, is not protected — accepted as
  out of scope.
- Settings live with the Apple account, not the journal: restoring the app on
  a new device recovers them via KVS, but handing the folder alone to someone
  else does not carry configuration.
- iCloud KVS is last-writer-wins with ~1 MB capacity — fine for a handful of
  strings, but templates must stay small (they are).
