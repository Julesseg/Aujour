import Foundation

/// A change to an Entry's text, said as the smallest rewrite that makes it:
/// which characters go, and what takes their place.
///
/// The form the editor can act on without losing anything it is holding.
/// Handing back a whole new Entry would be the same words, and would take the
/// cursor, the selection and the undo stack with it — a box ticked halfway
/// through a sentence would move the caret to the end of the day. So a change
/// says only what it changed, and the text view puts it through the same door
/// a keystroke goes through.
public struct MarkdownEdit: Equatable, Sendable {
    /// The characters this replaces, in the source's own UTF-16 offsets.
    public let range: NSRange

    /// What goes there instead.
    public let replacement: String

    /// Where to leave the cursor once it is in, in the offsets the text will
    /// have *after* the edit — or `nil` for an edit that has no opinion, which
    /// leaves the cursor wherever the editor was already holding it.
    ///
    /// Ticking a box has no opinion: a box ticked halfway through a sentence
    /// must not take the caret out of the sentence. A formatting control always
    /// has one, because the characters it wrote went in around the very place
    /// the user is writing — bold with a word selected has to leave that word
    /// selected, and not the two stars it just put in front of it.
    public let selection: NSRange?

    public init(range: NSRange, replacement: String, selection: NSRange? = nil) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// Where a cursor that was *here* ends up once this edit has gone in —
    /// what an edit with no opinion of its own leaves it at.
    ///
    /// "Where it was" is an offset, and an offset means a different character
    /// once something before it has been rewritten to a different length.
    /// Ticking a box never moves anything, because it writes one character
    /// over one; answering a placeholder writes a sentence where eight
    /// characters were, and a caret in the paragraph below would be left that
    /// many characters short of the word somebody was writing.
    ///
    /// Only an edit entirely before the cursor moves it. One that reaches into
    /// the cursor is an edit to the very characters it is on — a formatting
    /// control, which always says where it wants the cursor left — and this
    /// leaves that alone rather than guessing.
    public func cursorLeftWhere(it was: NSRange) -> NSRange {
        guard range.upperBound <= was.location else { return was }
        let moved = (replacement as NSString).length - range.length
        return NSRange(location: was.location + moved, length: was.length)
    }
}

extension MarkdownEdit {
    /// The edit that puts `markdown` into an Entry on a line of its own, at
    /// the caret.
    ///
    /// The one rule for anything that goes into a day as a line — a
    /// photograph's embed, a meeting's line from Suggestions — so that they
    /// are placed by one reading of "at the caret" and not two. Line breaks
    /// are added only where there is not one already, so a caret on the
    /// empty line the return key just made writes no blank lines around it.
    ///
    /// Nothing is taken out. A selection is not replaced the way typing over
    /// one is — the line goes in after it — because nobody adding a line
    /// meant to delete the words they had selected, and no words are ever
    /// silently discarded (`v1-decisions.md`).
    ///
    /// The cursor is left after the line, where the next one goes: which is
    /// what lets four meetings tapped one after another come out as one
    /// list, each landing after the last.
    public static func onItsOwnLine(
        _ markdown: String,
        in source: String,
        at selection: NSRange
    ) -> MarkdownEdit {
        let text = source as NSString
        // A caret reported past the end of the day is about a version of it
        // that has been replaced since — the end of the Entry is where the
        // line goes, rather than an exception in front of somebody who is
        // writing.
        let caret = min(max(selection.upperBound, 0), text.length)

        let onALineAlready = caret == 0 || text.character(at: caret - 1) == 0x0A
        let restOfTheLine = caret < text.length && text.character(at: caret) != 0x0A
        let replacement = (onALineAlready ? "" : "\n") + markdown + (restOfTheLine ? "\n" : "")

        return MarkdownEdit(
            range: NSRange(location: caret, length: 0),
            replacement: replacement,
            selection: NSRange(
                location: caret + (replacement as NSString).length,
                length: 0
            )
        )
    }
}

extension EntryMarkdown {
    /// The edit that ticks or unticks the box on the line `index` is on, or
    /// `nil` when nothing on that line is a box.
    ///
    /// What tapping a checkbox does, and the whole of it: one character
    /// between two brackets changes, and the Entry is plain markdown before
    /// and after — a file Obsidian ticked and a file Aujour ticked are the
    /// same file (ADR 0001). Nothing is reformatted, nothing is reordered, and
    /// a day full of tasks is not rewritten to tick one of them.
    ///
    /// `index` is anywhere on the line, because a tap lands on a box that is
    /// drawn over several characters and there is no useful distinction
    /// between them. Past the end of what was read it is the last line, which
    /// is where a tap at the bottom of an Entry lands.
    public func tickingTheBox(at index: Int) -> MarkdownEdit? {
        guard let line = line(holding: index), line.box.length > 0 else { return nil }
        guard case .taskItem(let isDone) = line.block else { return nil }

        return MarkdownEdit(
            // The one character between the brackets. The brackets themselves
            // are not touched, so an editor holding a selection across the
            // line keeps it.
            range: NSRange(location: line.box.location + 1, length: 1),
            replacement: isDone ? " " : "x"
        )
    }
}
