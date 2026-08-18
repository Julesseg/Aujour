import Foundation

/// The stretches of an Entry the editor draws as something other than their
/// own characters: a task item's box, an embed's picture, and an unanswered
/// interactive placeholder's widget.
///
/// Live preview's other half. ``HiddenSyntax`` says which marks are left out
/// of the drawing because what they mean is already on screen without them —
/// nothing takes their place, and the words either side simply close up. This
/// says which stretches are *stood in for*: `- [x] ` becomes a box the user
/// can tap, `![sunset](…)` becomes the picture it names, and `{{mood}}`
/// becomes the widget that asks it. All three are still every character of the
/// file, which has not changed and does not know (ADR 0001).
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

            /// An unanswered interactive placeholder's whole `{{name}}` token:
            /// the widget that asks it, which the app draws and the user taps
            /// to answer (``EntryMarkdown/answering(_:in:with:)``).
            ///
            /// Answered, there is no token left and so nothing here — which is
            /// the whole of how a widget goes away, and why nothing has to
            /// remember that this line was once a question.
            case widget(InteractivePlaceholder)
        }

        public let kind: Kind

        /// The characters the drawing stands in for, in the source's own
        /// UTF-16 offsets.
        public let range: NSRange
    }

    /// In the order they appear, and never overlapping. Two drawings over the
    /// same characters would be one of them drawn over nothing, so where they
    /// could reach each other — a placeholder's token inside an embed's alt
    /// text — the one that was found first keeps the stretch.
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
        var text = AddressableText(source)
        var elements: [Element] = []

        for line in markdown.lines {
            if case .taskItem(let isDone) = line.block, !line.range.isTouched(by: cursor) {
                elements.append(Element(kind: .taskBox(isDone: isDone), range: line.marker))
            }
            DrawnElements.pictures(in: line.inlines, of: &text, from: cursor, into: &elements)
        }
        // After the pictures, so that a token written inside an embed's alt
        // text is left to the picture that already covers it; and sorted at
        // the end, because a widget and a picture on the same line are found
        // in two passes and are drawn in the order they are written.
        DrawnElements.widgets(of: markdown, in: source, from: cursor, into: &elements)
        elements.sort { $0.range.location < $1.range.location }
        self.elements = elements
    }

    private static func pictures(
        in inlines: [MarkdownInline],
        of text: inout AddressableText,
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
            let target = text.text(in: inline.destination)
                .trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { continue }
            elements.append(Element(kind: .picture(target: target), range: inline.range))
        }
    }

    /// The widgets: one for every registered interactive placeholder still
    /// waiting to be answered, and none for a token the cursor is in — which
    /// is a token being edited as the text it is, exactly as a task's marker
    /// is at the cursor.
    private static func widgets(
        of markdown: EntryMarkdown,
        in source: String,
        from cursor: NSRange?,
        into elements: inout [Element]
    ) {
        for token in markdown.interactivePlaceholders(in: source) {
            guard !token.range.isTouched(by: cursor) else { continue }
            guard !elements.contains(where: {
                NSIntersectionRange($0.range, token.range).length > 0
            }) else { continue }
            elements.append(Element(kind: .widget(token.placeholder), range: token.range))
        }
    }
}

/// An Entry's text, made addressable by UTF-16 range the first time somebody
/// asks and not before.
///
/// Making it addressable costs the length of the whole Entry, and this is
/// built for every paragraph a keystroke lands in — nearly none of which hold
/// an embed whose target needs spelling out. So the cost is not paid until
/// there is something to pay it for, which is what keeps a keystroke costing a
/// paragraph in a day of any size.
private struct AddressableText {
    private let source: String
    private var addressable: NSString?

    init(_ source: String) {
        self.source = source
    }

    mutating func text(in range: NSRange) -> String {
        let addressable = self.addressable ?? source as NSString
        self.addressable = addressable
        return addressable.substring(with: range)
    }
}
