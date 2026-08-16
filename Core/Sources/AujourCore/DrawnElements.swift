import Foundation

/// The stretches of an Entry the editor draws as something other than their
/// own characters: a task item's box, and an embed's picture.
///
/// Live preview's other half. ``HiddenSyntax`` says which marks are left out
/// of the drawing because what they mean is already on screen without them —
/// nothing takes their place, and the words either side simply close up. This
/// says which stretches are *stood in for*: `- [x] ` becomes a box the user
/// can tap, and `![sunset](…)` becomes the picture it names. Both are still
/// every character of the file, which has not changed and does not know
/// (ADR 0001).
///
/// The two are kept apart because the invariant that makes hiding safe — only
/// syntax ever goes undrawn — is not true here, and should not be weakened to
/// make room. An embed's alt text is words, and the picture stands in for
/// those words too. What keeps *this* safe is the same cursor rule: a stretch
/// is only stood in for while the cursor is away from it, so the markdown is
/// on screen wherever somebody might edit it.
///
/// ## What Core cannot know
///
/// Whether the picture is there. A target that names no file in the Journal
/// Root is not a picture, and the app draws the embed's own text instead —
/// harmless, visible, and exactly what Obsidian would show. That is the app's
/// call to make because it is the only layer that can see the folder; this
/// type says where a picture *would* go and what it points at, and an element
/// the app cannot resolve it simply does not draw.
public struct DrawnElements: Equatable, Sendable {
    /// One stretch and what is drawn over it.
    public struct Element: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// A task item's `- [x] ` marker: a box, ticked or not, that the
            /// user taps to rewrite the line (``EntryMarkdown/tickingTheBox(at:)``).
            case taskBox(isDone: Bool)

            /// An embed's whole span: the picture at `target`, which is a
            /// path or a file name relative to the Journal Root or to the
            /// Entry — resolving it is the app's, which is the layer with a
            /// folder to look in.
            case picture(target: String)
        }

        public let kind: Kind

        /// The characters the drawing stands in for, in the source's own
        /// UTF-16 offsets.
        public let range: NSRange
    }

    /// In the order they appear, and never overlapping — a picture's span and
    /// a task's marker cannot reach each other, because a marker stops where
    /// the words begin.
    public let elements: [Element]

    /// Reads a reading: what the editor draws instead of the text, given
    /// where the cursor is.
    ///
    /// - Parameters:
    ///   - markdown: what was read — the whole Entry, or the paragraph a
    ///     keystroke landed in.
    ///   - source: the text it was read from, which is where an embed's
    ///     target is spelled out.
    ///   - cursor: where the cursor is, or `nil` for nobody writing here —
    ///     which stands in for everything, because a day nobody is writing in
    ///     is a day being read.
    public init(_ markdown: EntryMarkdown, in source: String, cursor: NSRange?) {
        var text = Spelling(source)
        var elements: [Element] = []

        for line in markdown.lines {
            if case .taskItem(let isDone) = line.block, !line.range.isTouched(by: cursor) {
                elements.append(Element(kind: .taskBox(isDone: isDone), range: line.marker))
            }
            DrawnElements.pictures(in: line.inlines, of: &text, from: cursor, into: &elements)
        }
        self.elements = elements
    }

    private static func pictures(
        in inlines: [MarkdownInline],
        of text: inout Spelling,
        from cursor: NSRange?,
        into elements: inout [Element]
    ) {
        for inline in inlines {
            guard inline.style == .image else {
                // An embed inside a link is not a thing anybody writes, but an
                // emphasised one is — `*![a](b)*` — and the picture is found
                // where it is written.
                pictures(in: inline.inlines, of: &text, from: cursor, into: &elements)
                continue
            }
            guard !inline.range.isTouched(by: cursor), inline.destination.length > 0 else {
                continue
            }
            let target = text.string(in: inline.destination)
                .trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { continue }
            elements.append(Element(kind: .picture(target: target), range: inline.range))
        }
    }
}

/// The source, ready to be asked what a range of it says — and not before.
///
/// This is asked of every paragraph a keystroke lands in, and nearly every
/// paragraph has no embed in it. Reaching into the text costs the length of
/// the Entry rather than the length of the line, so it is not done at all
/// until something needs a target spelled out — which is what keeps a
/// keystroke costing a paragraph in a day of any size.
private struct Spelling {
    private let source: String
    private var reachable: NSString?

    init(_ source: String) {
        self.source = source
    }

    mutating func string(in range: NSRange) -> String {
        let reachable = self.reachable ?? source as NSString
        self.reachable = reachable
        return reachable.substring(with: range)
    }
}
