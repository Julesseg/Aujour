# 0005 — The Content Template is a file the user picks, read where it lies

Date: 2026-08-19
Status: accepted

## Context

A new Entry is spawned from a Content Template. The template had to live
somewhere, and the first implementation kept its markdown inside the settings
themselves — a string synced between the user's devices through iCloud
key-value storage (ADR 0003), typed into a text field on a settings screen.

That works, and it is wrong for this app. Obsidian's daily notes name a
*template file* in the vault ("Template file location"), and Aujour's whole
premise is that an existing daily-notes setup carries over unchanged: the Path
Template pastes in verbatim, the placeholders are Obsidian's own. A user who
already has a `Daily.md` should point at it, not paste a copy of it into a
second app — and a copy is what a stored string is, from the moment they next
edit the file.

Where that file may sit is the second question. Templates are not journal
content: people keep them in a `Templates` folder in their vault, in iCloud
Drive, in a notes folder that has nothing to do with the journal. Confining
the setting to files inside the Journal Root would keep it syncable, at the
cost of telling a good many users to move a file they had a reason to put
where it is.

## Decision

The Content Template is a file the user picks with the system's file picker,
from anywhere on the device, and Aujour reads it each time it spawns a day. No
template is a blank page.

How the file is remembered depends on where it turns out to be, and this is
decided when it is picked:

- **Inside the Journal Root** — the path relative to the folder is the whole
  reference. It is read through the Journal Store, and it travels in the
  journal-shaping settings (ADR 0003): the folder syncs, the file goes with
  it, and the user's other device needs telling nothing.
- **Anywhere else** — a security-scoped bookmark, kept in local storage on the
  device that made it. A bookmark means nothing on another device, so nothing
  about this case travels, and the other device is pointed at its template
  once — exactly as it is pointed at its journal folder, which has always been
  per-device for the same reason (ADR 0003).

Picking either way forgets the other, so there is only ever one template.

A template that cannot be read spawns a blank page rather than failing the
day. The file belongs to the user: they may have renamed it, moved it, left it
on a drive they unplugged, or not yet had it down from iCloud. A day that
refused to open because of a missing template would be a day they cannot write
in, which is worse than the blank page they had before they set one. The
screen says which file it is pointed at, and says so when it cannot reach it;
that is where an unreachable template belongs, not in the editor.

## Consequences

- Editing the template in Obsidian changes tomorrow's Entry. There is no copy
  in Aujour to go stale, and no import step to repeat.
- Spawning reads a file, so it is asynchronous and can fail; it fails soft, to
  a blank page. The domain does not know where the file is — `EntryEditor`
  takes a `ContentTemplateSource` and the App layer decides what that reads,
  which is what keeps bookmarks and security scopes out of Core.
- A template outside the folder is per-device. Two devices can disagree about
  what a new day starts from, which is a weaker promise than the other
  journal-shaping settings make. It is the same trade the Journal Root
  bookmark already makes, and the way to avoid it is to keep the template in
  the journal folder — which the screen says.
- Aujour now reads one file that is not an Entry, an Attachment or a Parked
  File, and may read one outside the Journal Root entirely. It still writes
  none: the template is read-only, and only because the user pointed at it.
