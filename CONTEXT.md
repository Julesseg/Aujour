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

### Migration
Moving the Entries already in the Journal Root into the shape a newly chosen
Path Template names. Offered whenever the Path Template changes, and
skippable: declining leaves the old files exactly where they are, where they
stop being Entries and stop being surfaced anywhere in the app — orphans the
user manages in Files or Obsidian, and which Aujour keeps no list of
(ADR 0002).

A migration is planned before any of it happens, because the plan is what the
offer is made of: which file goes where, and which days already have a file
sitting at the path they would move to. Those are collisions, and the user
confirms them — the file that is there stays as that day's Entry, and the
incoming one is kept beside it as a Parked File. Nothing is ever overwritten,
and nothing is ever deleted.

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

### Styled Source
How the editor shows an Entry: the markdown drawn as what it means — headings
large, emphasis slanted, list markers set apart, quotes in somebody else's
voice. Nothing is added and nothing is rewritten, so the text in the editor is
the text in the file, character for character. Which characters are *drawn* is
a separate question, and Live Preview's.

A line is the unit. What shape a line is — heading, list item, quote — is read
from that line alone, and the spans inside it never reach past its ends. That
rules out what needs more than a line to recognise (a fenced code block; a
heading inside a quote is quoted text), and it is what makes a keystroke cost
a paragraph rather than a day: the editor re-reads the paragraph the typing
landed in, which is only the same answer as re-reading the Entry because the
answer was never about the rest of it.

### Live Preview
Styled Source with the marks left out where nobody is writing: the `#` before
a heading and the `**` around a bold word are not drawn while the cursor is
elsewhere, and are drawn again the moment it enters that element. The Entry
reads like a document everywhere the user is not, and like markdown exactly
where they are — so a mark is always visible where it might be typed, aimed
at or deleted.

Only a mark whose meaning survives without it may go. A heading's hashes may,
because the line stays large; a bullet's `- ` may not, because the marker is
the only thing that says "list". Hiding is done by leaving the character out
of the *drawing* — never out of the text, which stays byte for byte the file
on disk (ADR 0001). Selecting, copying and deleting all reach every character,
hidden or not.

A day nobody is writing in has no cursor in it, and so no marks anywhere: the
keyboard going down leaves a document to read rather than the last heading
still showing its hashes.

### Element
The thing the cursor is in, for the purposes of Live Preview: one heading, one
emphasised phrase, one link. Elements answer one at a time and not by line —
standing in a heading does not reveal the emphasis further along it — and an
element's ends count as inside it, because a caret against the closing `*` is
a caret editing that emphasis.

### Drawn Element
A stretch of an Entry the editor draws as something other than its own
characters: a Task's box, and an Embed's picture. Live Preview's other half —
where hiding leaves a mark out of the drawing because what it means is already
on screen without it, a Drawn Element is *stood in for*, and something takes
its place.

Held to the same cursor rule, and for the same reason: a stretch is only stood
in for while the cursor is away from it, so the markdown is on screen wherever
somebody might edit it and nobody ever deletes a character they could not see.
Nothing is added to the text to hang the drawing on — the box and the picture
are laid out over characters the file already has, which stay selectable,
deletable and in the file (ADR 0001).

A picture nobody can find is not a Drawn Element at all: an Embed whose target
names no file in the Journal Root is left as the markdown it is, visible and
harmless, exactly as Obsidian shows it.

### Task
A list item whose first word is a box: `- [ ]` or `- [x]`. Drawn as a checkbox
the user taps, and tapping it rewrites one character of the Entry — the file is
plain markdown before and after, so a task Aujour ticked and a task Obsidian
ticked are the same file. A finger on the box is one way to that character and
the Accessory Row's checkbox control is the other, which is what a box drawn
over characters rather than built as a view leaves for VoiceOver.

### Embed
An Attachment referenced from an Entry, in either of the two spellings a vault
holds: standard markdown `![alt](path)` and Obsidian's `![[target]]`. Both are
drawn as the picture they name wherever they are written; the embed-syntax
Journal Setting decides only what Aujour itself *writes*.

Where a target points is resolved against the Entry holding it first and the
Journal Root second; a target that is only a file name is then looked for
anywhere in the folder, which is what a wiki embed means and what Obsidian
does for a markdown link too — so both spellings are searched for the same
way. Never outside the Journal Root: a target that climbs past it names
somebody else's file and resolves to nothing.

### Accessory Row
The formatting bar above the keyboard: headings, bold and italic, lists,
checkboxes, indenting, and a photograph. On screen exactly while an Entry is
being written in, and gone with the keyboard — a day being read has neither.

Every control is a shortcut for markdown the user could have typed by hand, so
each one is a rewrite of the characters that are already there and the Entry is
plain markdown before and after. A control acts on what the cursor is on: the
word a caret stands in or the words that are selected for the ones that wrap,
and every line the selection touches for the ones that are about lines — a line
with nothing on it included, since a list is most often started on the empty
line the return key just made.

Each is its own way back: bold inside a bold word takes the marks away, a
bullet on a list of bullets takes the markers away. Three exceptions earn
themselves — a heading at another level is re-levelled rather than removed,
because nobody presses *Heading 2* meaning "not a heading"; bold at the end of
a bold word steps the cursor out past the closing marks, because that is
somebody who has finished writing it rather than somebody who wishes they had
not; and the checkbox goes round three states rather than two — a Task, a Task
that is done, and neither — because a box is drawn over characters rather than
being a view, so this is the only way to tick one without a finger on the
glass.

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
