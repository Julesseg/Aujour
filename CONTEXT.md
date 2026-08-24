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
The markdown file a new Entry is spawned from — picked with the system's file
picker from anywhere on the device, and read afresh every time a day is
spawned (ADR 0005). Editing it in Obsidian is what changes tomorrow's Entry;
Aujour keeps no copy. Inside the Journal Root it is remembered as a path and
travels to the user's other devices; anywhere else it is a security-scoped
bookmark this device holds alone. Placeholders use Obsidian's `{{name}}` /
`{{name:FORMAT}}` syntax; the Obsidian core set is supported verbatim so an
Obsidian daily-note template is pointed at unchanged, and Aujour-specific
placeholders (e.g. {{events}}) extend the same syntax. No template, or one
that cannot be read, is a blank page.

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
  at spawn from on-device data, formatted per user settings. Resolved for the
  Entry's *Journal Day* — a Monday filled in on Tuesday gets Monday's meetings
  — and what lands in the file is plain markdown, so an Entry read in Obsidian
  needs nothing resolved again.

  What they read is asked for through a seam and never fetched by the domain
  itself, which is what lets a day with no calendar be a day with nothing in
  it rather than a failure: a permission the user refused, a device with no
  such data, and a genuinely empty day all render per the formatting settings,
  and none of them stops the Entry appearing. Asking *for* the permission is a
  separate act, done before a day is opened — a spawn waiting on a system
  alert would be an Entry that does not appear until somebody answered one.
- **Interactive placeholders** ({{mood}}, {{location}}, …) — remain literal
  `{{name}}` text in the file until answered; Aujour renders them as inline
  widgets in the editor, and answering one replaces it with plain markdown
  text. Unanswered ones are harmless literal text in Obsidian.

Photos are deliberately *not* a placeholder: that day's photos are offered by
Photo Suggestions and inserted as Attachments where the user chooses.

### Day Data
What the device can say about a Journal Day, as everything above it sees: one
source per data placeholder, each answering a stretch of wall-clock time with
the day's items — a title, and the hour it sits at where it has one. The
second seam between the domain and the device, and the Journal Store's
opposite number: the domain asks what a day held and never learns whether the
answer came from EventKit, from a fake, or from nowhere.

Reading through it cannot fail, which is the whole of its shape. A permission
the user refused, a device with no such data and a genuinely empty day all
arrive as no items — never as an error — so no Entry ever fails to appear
because a calendar would not answer. Asking *for* a permission is a separate
act on the same seam, done before a day is opened rather than while one is
being spawned.

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
characters: a Task's box, an Embed's picture, and an unanswered interactive
Placeholder's Widget. Live Preview's other half — where hiding leaves a mark
out of the drawing because what it means is already on screen without it, a
Drawn Element is *stood in for*, and something takes its place.

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

### Widget
What an unanswered interactive Placeholder is drawn as: a pill carrying the
placeholder's name, standing where its `{{name}}` token is written and tapped
to answer it. Answering replaces the token with plain markdown — the words the
widget handed over, and nothing else — after which there is no token, and so
no widget.

Nothing anywhere records which questions are outstanding, because the token is
the record. An unanswered one is literal text: harmless in Obsidian, untouched
by every tool that is not Aujour, and a widget again the next time Aujour opens
the day — the same answer read from the same characters. Cancelling therefore
writes nothing at all, and a token the cursor is in is text like any other,
which is how one is answered by typing over it.

Adding a placeholder is registering it: the machinery is by name, and what is
left is the pill's word and what answering it asks.

### Place
Somewhere that can be named: what a `{{location}}` Widget offers, and — once
it is confirmed — the plain text that stands where the token did. A name, and
in the picker only, enough of an address to tell it from the other place of the
same name two streets over. Never a coordinate: nobody writes one in their
journal. What is written is the name and nothing else, whichever of the two
ways below found it.

The Widget is about the Journal Day rather than about now, so it reads two
things at once. **Where the day was photographed**: the positions that day's
own pictures carry, gathered into Stops and named one apiece. **Where the
device is now**: the named places around it, nearest first and each with how
far off it is, and the area they all sit in.

The two are offered apart rather than run together — "Near you" and "From
photos" — because where a suggestion came from is worth seeing: one is a claim
about this minute and the other about the day being written, and which of them
to trust is the user's to judge. A heading with nothing under it is not drawn.

Two judgements sit over that. Between a named place and the area it is in, the
named one leads only when it is close enough to be where somebody *was* —
otherwise the area does, because a specific place that is merely nearby is a
wrong answer somebody would confirm with one tap, and vague and right beats
specific and wrong. Between the day's photographs and the live fix, the fix
leads only for a day still being lived: a Monday written up on Friday would
otherwise be offered Friday's street as where somebody was on Monday, and the
photographs from that Monday already know better. Everything found is in the
picker either way, and a place found both ways is offered once, under the
heading that found it best.

The offer rides two permissions and needs neither. Somebody who refused the
device's location is still offered the places their day's pictures were taken —
naming a coordinate the library handed over is a question about the map, not
about where this device is — and somebody who refused the library is still
offered the live fix.

The place is *offered*, never assumed. A permission nobody has been asked about
is offered to be looked at, in the words of the thing it would actually read; a
day with no photographs, photographs that carry no position, and a refusal are
all a Widget with less under it, and all of them together are a Widget with
nothing under it and a field the place is typed into instead. None of those is
a failure and none is said out loud — the question in front of the user is
where they were, and they already know the answer.

### Stop
Somewhere a day stopped, as its photographs recorded it: the positions that sit
together, taken as one, timed by the earliest of them. Somebody photographs
their lunch four times from the same table, and what they would write in their
journal is one café.

The photographs are how a place is *worked out*, and they stop at the offer.
Nothing of them reaches the Entry — not the hour, not the position, not which
picture it came from. The time a Stop carries is what puts the day's places in
the order the day made them, and what tells two of them apart when they come
back with the same name.

Gathering happens over arithmetic and *before* anything is named, which is what
keeps the naming affordable: putting a name to a position is a round trip to a
map server, so a day of two hundred photographs and a day of three cost the
same handful of lookups. A day that went to more places than are worth naming
offers the ones it was spent at — where most of its pictures were taken —
because a single frame through a train window is what gives way.

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

An Attachment is named after the Journal Day it was added to —
`2026-03-14.jpg`, then `2026-03-14-2.jpg` for the next one that day — so that
a folder of them sorts the way the journal does, and so that the name a wiki
embed is resolved by across the whole vault is one that could only be this
journal's. Nothing is ever written over: neither the path nor the name is one
the folder already holds, because an embed whose path names nothing is looked
for by name and a photograph sharing a name with somebody's note is a
photograph the editor might draw the wrong one of.

The formats kept are the ones anything can open — JPEG, PNG, GIF. Anything
else is converted to JPEG on the way in, HEIC first among them: it is what an
iPhone camera writes and what the same folder opened on a Windows laptop
cannot show. That conversion is the one edit Aujour makes to somebody's
photograph.

### Photo Suggestions
The day's own photographs, offered under the day being written: "N photos from
this day", a strip of thumbnails, and one tap that adds one. What it offers is
the photographs taken during the Entry's *Journal Day* — midnight to midnight
where the device is, the same stretch Day Data reads — so a Monday filled in on
Friday is offered Monday's. A tap goes through the attachment pipeline like any
other photograph, so the file lands under the Attachment Path Template and the
Entry points at it in the embed syntax in force.

Read through a seam, like Day Data and for the same reasons: reading never
fails and never asks, so a device with no library, a permission refused and a
day the camera missed all arrive as nothing to offer — which is a panel that is
simply absent, never a notice and never a journal that would not open.

One of the two things in Aujour that ask for the photo library — the
`{{location}}` Widget asks for it too, to read where the day's photographs were
taken — and both ask because the user tapped the offer to look, never because a
day was opened. What the system says when it asks speaks for both, rather than
leaving the larger claim to the sentence this panel would have asked with.
Saying no costs the panel and the places from photographs, and nothing else:
adding a photo from the Accessory Row goes through the system picker, which
runs in a process of its own and needs no permission at all.

### Journal Settings
The settings that shape the Journal itself: Path Template, Content Template,
Attachment Path Template, embed syntax, Rollover Hour, and how each data
placeholder is written out — the marker its items' lines start with, the
marker for one the day already saw through, the format their times take, and
what it says on a day that held nothing. Two devices may not disagree about
these — different Path Templates would write the same Journal Day to two paths
— so they travel between the user's devices through iCloud key-value storage
(ADR 0003). No settings are ever written into the Journal Root.

### Device Settings
The settings that belong to one device: theme, editor font, and the time of
the daily reminder. Nothing here shapes what is written into the Journal, so
a dark-themed iPhone and a light-themed iPad are not in disagreement. Device
Settings stay on the device that set them and never reach the synced seam.
