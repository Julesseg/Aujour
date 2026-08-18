import Foundation

/// What the return key means inside a list: the next item, already begun.
///
/// A list is the one place in markdown where a line's first characters are not
/// the user's to type. Somebody writing a shopping list types `- ` once and
/// then the milk, the bread and the eggs — and every editor that has ever held
/// a list opens the next item for them. Without it a list is a line of
/// punctuation retyped per item, on a keyboard where `-` is a shifted layout
/// away.
///
/// Nothing is added that the user could not have typed and nothing is styled:
/// this is characters going into the file at the caret, exactly as if they had
/// been typed there, and the Entry is plain markdown before and after
/// (ADR 0001). What comes back out of the folder is what the editor held.
///
/// ## Where a list ends
///
/// On the item nobody typed into. A return at the end of `- ` takes the marker
/// away and leaves an empty line, which is the way out of a list on every
/// keyboard there is — and the only way out that does not mean deleting
/// characters the editor put there. Pressing return twice, then, is how a list
/// stops: once for an item, once for none.
public enum MarkdownReturn {
    /// The edit a return at `selection` makes, or `nil` for a return that is
    /// just a return — anywhere but in a list, and anywhere in a list's own
    /// marker, where the caret is among characters that say what the line is
    /// rather than among its words.
    ///
    /// Only the lines around the caret are read, unlike the whole-Entry reading
    /// a control on the accessory row pays for (``MarkdownFormatting``): this
    /// is on the typing path, where a keystroke may cost a paragraph and never
    /// a day (``EntryMarkdown/init(_:around:)``).
    public static func edit(_ source: String, over selection: NSRange) -> MarkdownEdit? {
        let text = source as NSString
        let start = min(max(selection.location, 0), text.length)
        let cursor = NSRange(
            location: start, length: min(max(selection.length, 0), text.length - start)
        )

        let reading = EntryMarkdown(source, around: cursor)
        guard let line = reading.line(holding: cursor.location),
            let marker = nextItem(after: line, in: text)
        else { return nil }
        // A caret inside the marker is a caret in the characters that make the
        // line a list item, not in the item. A return there splits them, and
        // splitting them is what the user asked for.
        guard cursor.location >= line.marker.upperBound else { return nil }

        // The item nobody typed into: the list ends, and what is left is the
        // empty line it would have been without any of this.
        if line.content.length == 0, cursor.length == 0 {
            return MarkdownEdit(
                range: line.range,
                replacement: "",
                selection: NSRange(location: line.range.location, length: 0)
            )
        }

        // Under the item above it, and as deeply indented: a nested list goes
        // on being nested.
        let opened = "\n" + text.substring(with: line.indent) + marker
        return MarkdownEdit(
            range: cursor,
            replacement: opened,
            selection: NSRange(
                location: cursor.location + (opened as NSString).length, length: 0
            )
        )
    }

    /// The marker the next item carries, or `nil` where the line above is not
    /// a list item at all.
    ///
    /// The line's own marker, character for character — `*` stays a `*`, and a
    /// list somebody spaced out as `-   milk` goes on being spaced that way.
    /// With the two things the next item cannot simply inherit: its number,
    /// and whether it is done.
    private static func nextItem(after line: MarkdownLine, in text: NSString) -> String? {
        let marker = text.substring(with: line.marker)
        switch line.block {
        case .bulletItem:
            return marker

        case .taskItem:
            // A task to do, whatever the one above it says. Nobody opens the
            // next line of a list having already done it.
            guard line.box.length > 0 else { return marker }
            let next = NSMutableString(string: marker)
            next.replaceCharacters(
                in: NSRange(location: line.box.location + 1 - line.marker.location, length: 1),
                with: " "
            )
            return next as String

        case .numberedItem(let number):
            // The next number, and then whatever the user wrote after theirs —
            // a `)` stays a `)`.
            let digits = marker.prefix { $0.isNumber }
            return "\(number + 1)" + marker.dropFirst(digits.count)

        // A return at the end of a heading opens a paragraph, which is what
        // the next line after a heading nearly always is; at the end of a
        // quote it opens a line outside the quote, because a quote is somebody
        // else's voice and the user is back in their own.
        case .blank, .paragraph, .heading, .quote, .thematicBreak:
            return nil
        }
    }
}
