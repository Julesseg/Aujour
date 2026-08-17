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
        let line = lines.first { index < $0.paragraph.upperBound } ?? lines.last
        guard let line, line.box.length > 0 else { return nil }
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
