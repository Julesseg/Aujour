# Aujour — Ubiquitous Language

Aujour is a journaling app built on plain markdown files: one file per day,
living in a user-visible folder that can coexist with an Obsidian vault.

## Glossary

### Journal
The user's entire body of journaling: the tree of Entries under the Journal
Root. There is exactly one Journal per app installation. The Journal is fully
defined by the files on disk — Aujour holds no journal content of its own.

### Journal Root
The folder the Journal lives under. Defaults to a folder Aujour owns (visible
in the Files app); the user may instead point it anywhere they can pick in the
Files app — typically inside an Obsidian vault.

The default is Aujour's own iCloud Drive folder, and on a device where iCloud
Drive is off it is the app's folder under "On My iPhone" instead. Which one a
journal uses is decided on first launch and then never changes on its own — a
journal that moved between the two behind the user's back would be a journal
with holes in it (ADR 0004).

### Journal Store
The Journal Root as everything above the file system sees it: a set of files
addressed by paths relative to the root, which can be enumerated, read, written
and moved. The single seam between the domain and storage — the domain asks a
Journal Store which days are journaled and what an Entry says, and never learns
whether the answers come from iCloud Drive, a folder in an Obsidian vault, or
memory. Nothing about a particular file system (bookmarks, file coordination,
download state) crosses it; the in-memory Journal Store the tests journal into
is a full-fledged one.

### Entry
One markdown file representing one Journal Day. At most one Entry exists per
Journal Day. An Entry's identity is its date, not its filename — the filename
and location are derived from the date via the Path Template.

### Journal Day
The date an Entry belongs to. Usually the calendar date, but the current
Journal Day does not advance until the Rollover Hour: with a 4 AM rollover,
1 AM on March 2nd still belongs to Journal Day March 1st. "Today's Entry"
means the Entry for the current Journal Day.

### Rollover Hour
A setting: the time of day at which the current Journal Day advances.
Defaults to midnight, which matches Obsidian's daily-notes behavior exactly.

### Path Template
A Moment-format string, relative to the Journal Root, that maps a date to an
Entry's file path — e.g. `YYYY/MM/YYYY-MM-DD` (the default). Slashes create
subfolders, literal text goes in `[brackets]`, and `.md` is appended
automatically. A file is an Entry exactly when its path matches the current
Path Template for some date (see ADR 0002 for what happens on change).

The supported tokens are `YYYY`, `MM` and `DD` — the zero-padded numeric ones,
which have fixed widths and so read back unambiguously. Anything else (`MMMM`,
`ddd`, `D`, `YY`, …) is rejected, and an Entry template must name all three so
that every path identifies exactly one day.

### Content Template
The markdown skeleton a new Entry starts from. Placeholders use Obsidian's
`{{name}}` / `{{name:FORMAT}}` syntax; the Obsidian core set is supported
verbatim so an Obsidian daily-note template pastes over unchanged, and
Aujour-specific placeholders (e.g. {{events}}) extend the same syntax.

### Spawn
Starting a Journal Day's Entry from the Content Template: the template
rendered for that day, put in front of the user to write into. A spawned Entry
is not yet a file — nothing is written until the first edit, so a day that was
opened and not written on leaves nothing behind, and "there is a file at the
Entry's path" goes on meaning "that day is journaled".

### Calendar
The Journal seen a month at a time: every Journal Day of a month, marked where
its Entry file exists. The marks are a scan of the Journal Root against the
current Path Template and are kept nowhere else — a disposable cache in ADR
0001's sense, where deleting it loses nothing and rebuilding it *is* reading
the journal. The Calendar is also the way into a day: every day up to today
can be opened (see Backfill), and days that have not arrived are shown and
locked.

### Backfill
Writing a past Journal Day after the fact: opening a day whose Entry does not
exist and spawning it for *that* day, so a Monday nobody wrote on is not a
permanent hole in the Journal. Reached from the calendar, where every day up
to today can be opened; days that have not arrived are shown and locked, since
there is no Entry to write before the day exists. A backfilled day is spawned
and saved exactly like today's — the file appears at the first edit — and the
Content Template's dates describe the day being written about, carrying the
clock time it is being written at.

### Placeholder
A `{{name}}` token in the Content Template (or typed directly into an Entry).
Three kinds:
- **Core placeholders** ({{date}}, {{time}}, {{title}}, plus {{yesterday}} and
  {{tomorrow}}) — static text resolved when the Entry is spawned; the same set
  Obsidian's daily notes resolve, so a template pastes over unchanged.
  {{date}} and {{time}} also take a `±Nunit` offset, as in
  `{{date-1d:YYYY-MM-DD}}`; an offset shifts when a placeholder is measured,
  never what it renders.
- **Data placeholders** ({{events}}, {{reminders}}, {{workout}}, …) — resolved
  at spawn from on-device data, formatted per user settings.
- **Interactive placeholders** ({{mood}}, {{location}}, …) — remain literal
  `{{name}}` text in the file until answered; Aujour renders them as inline
  widgets in the editor, and answering one replaces it with plain markdown
  text. Unanswered ones are harmless literal text in Obsidian.

Photos are deliberately *not* a placeholder: that day's photos are offered by
a suggestion panel and inserted as Attachments where the user chooses.

### Divergence
Two versions of one Journal Day that were both written — the Entry edited on
two devices while one of them was offline, which iCloud brings back as a
conflict it has no opinion about. Aujour has none about their contents either:
nothing is merged and nothing is discarded. The version written last keeps the
Entry path, every other version becomes a Parked File beside it, and the app
says so where the user is writing.

### Parked File
A file set aside as `{filename}_1.md` beside an Entry when two files claim
the same day — a template-migration collision, or sync divergence where the
older version loses the Entry path. Parked Files are never Entries; they hold
content awaiting a manual merge, and sit adjacent to the Entry precisely so
the user notices them in Obsidian or Files. The suffix is the first free one
— `_1`, then `_2`, and so on — because a `_1` already in the folder is
somebody's unmerged words too, and nothing is ever written over.

### Attachment
A non-markdown file (typically a photo) referenced by an Entry. Attachments
live under the Attachment Path Template — the same Moment format restricted to
folders (no `.md`, and it need not name a day), relative to the Journal Root,
default `[attachments]/YYYY/MM` — and are referenced
relatively from Entries. Embeds are written in standard markdown syntax by
default (Obsidian wiki-style available as a setting); Aujour renders both.

### Journal Settings
The settings that shape the Journal itself: Path Template, Content Template,
Attachment Path Template, embed syntax, and Rollover Hour. Two devices may
not disagree about these — different Path Templates would write the same
Journal Day to two paths — so they travel between the user's devices through
iCloud key-value storage (ADR 0003). No settings are ever written into the
Journal Root.

### Device Settings
The settings that belong to one device: theme, editor font, and the time of
the daily reminder. Nothing here shapes what is written into the Journal, so
a dark-themed iPhone and a light-themed iPad are not in disagreement. Device
Settings stay on the device that set them and never reach the synced seam.
