# 0005 — The Content Template is a file in the Journal Root, not text Aujour keeps

Date: 2026-08-19
Status: accepted

## Context

A new Entry is spawned from a Content Template. The template had to live
somewhere, and the first implementation kept its markdown inside the settings
themselves — a string synced between the user's devices through iCloud
key-value storage (ADR 0003), typed into a text field on a settings screen.

That works, and it is wrong for this app. Obsidian's daily notes name a
*template file* in the vault ("Template file location"), and Aujour's whole
premise is that an existing daily-notes setup carries over unchanged: the
Path Template pastes in verbatim, the placeholders are Obsidian's own. A user
who already has `templates/Daily.md` should point at it, not paste a copy of
it into a second app — and a copy is what a stored string is, from the moment
they next edit the file.

## Decision

The Content Template setting is a path to a markdown file, relative to the
Journal Root, and Aujour reads that file each time it spawns a day. Empty
means no template, which is a blank page.

The file must be inside the Journal Root. A file anywhere else on the device
would be reachable only through a security-scoped bookmark, which is
per-device and does not sync — and a journal-shaping setting that means
something different on the iPad is exactly what ADR 0003 exists to prevent.
Inside the folder, the path is as portable as the journal is: the vault
carries the template with it.

A template that cannot be read spawns a blank page rather than failing the
day. The file belongs to the user, in their own folder: they may have renamed
it, moved it, or not yet had it down from iCloud. A day that refused to open
because of a missing template would be a day they cannot write in, which is
worse than the blank page they had before they set one.

## Consequences

- Editing the template in Obsidian changes tomorrow's Entry. There is no copy
  in Aujour to go stale, and no import step to repeat.
- Spawning reads the folder, so it is asynchronous and can fail; it fails
  soft, to a blank page.
- Only the path travels through the KVS seam — a shorter value than a
  template, and one that stays well inside the ~1 MB budget.
- Aujour now reads one file in the Journal Root that is not an Entry, an
  Attachment or a Parked File. It still writes none: the template is read
  only, and only because the user pointed at it.
- A user whose template lives outside their journal folder has to move or
  copy it in. This is the price of the setting meaning the same thing on both
  their devices.
