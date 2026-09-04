# 0007 — The Frontmatter is cut off the file before the editor sees it

Date: 2026-09-05
Status: accepted

## Context

ADR 0001 named YAML frontmatter as the vehicle for per-entry metadata, and
nothing had been built on it: a file opening with `---` was drawn as a rule,
some paragraphs and another rule. Showing a Frontmatter as Properties — each
value with the input its kind deserves, a checkbox for `done`, a date picker
for `created` — had to go somewhere, and the obvious place is where every
other piece of markdown is drawn as what it means: inside the text view, as a
Drawn Element over its own characters, revealed as raw YAML when the cursor
enters it.

That obvious place collides with the rule the editor is built on. Styled
Source reads each line alone — what shape a line is never depends on another
line — and that is what lets a keystroke cost one paragraph's re-read rather
than the day's. Fenced code was ruled out for that reason. A Frontmatter is
worse than fenced code: an opening fence on line one changes what line eight
means, and a closing fence deleted changes what every line after it means.
Drawing it inside the text view means the parser carrying position, the
per-paragraph restyle proof no longer holding at the top of the file, and
every future editor change reasoning about the one block that breaks the
rule.

## Decision

The Frontmatter is cut off the file before the body reaches the editor, and
joined back to it, byte for byte, on save. The text view holds the body and
only the body; the Frontmatter is a section of its own above it, drawn as
Properties or as source, and that section is what the rounded corners and the
typed inputs belong to.

The cut is made by Obsidian's rule and no looser one, and the join is the same
characters in the same order, so the file on disk does not know which side of
the cut a line sat on. Reading a body as it is typed by that same rule is what
lets a Frontmatter written by hand lift into the section, and a fence deleted
in source mode drop its lines back into the body.

The price is one exception to two glossary promises. "The text in the editor
is the text in the file" becomes true of the body. Live Preview's promise that
the markdown is on screen wherever somebody might type it is kept for the
block by a source toggle rather than by the cursor rule — and the lift of a
hand-typed block *does* wait for the cursor to leave, so the promise that
nobody deletes a character they cannot see holds in the one place it could
have failed.

## Considered Options

- **A Drawn Element inside the text view.** Rejected above: it breaks the
  line-is-the-unit invariant that keeps the editor fast and its restyle
  provably local, for the sake of one block at a fixed position.
- **Understanding the YAML per Property**, with unknown constructs shown raw
  beside understood ones. Rejected: it needs a guess about where an unknown
  construct ends, and a wrong guess rewrites somebody's vault. The block is
  understood whole or not at all.

## Consequences

- Every Property control writes through the Entry Editor's content, so the
  debounced autosave, the reload-while-clean policy and Divergence handling
  all cover a Property edit unchanged.
- The Frontmatter parser is Core code with tests and keeps line ranges per
  Property, because a control's write touches that Property's lines and no
  others. A YAML library would model more than it can write back.
- Search, the Search Index, and sharing see the joined file and need no
  change; the Frontmatter is the day's text.
