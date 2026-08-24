import Foundation

/// The words an answered interactive placeholder is written down as, with a
/// slot where the answer goes: `Today's mood: {value}` becomes
/// `Today's mood: 4/5`.
///
/// ``MomentFormat``'s opposite number. A Moment format says how to render
/// something the device knows; this says how to word something only the user
/// knows, and it is the whole of what `{{name:FORMAT}}` means for a placeholder
/// the user answers rather than one the app resolves.
///
/// A template writes one to have a day's questions read as its own sentences —
/// `{{mood:Woke up feeling {value}}}` — and a placeholder that carries none is
/// written down in its own default (``InteractivePlaceholder/defaultFormat``),
/// which is a format like any other. There is one rule and no special case:
/// what a token writes is a pattern with the answer in its slot.
///
/// ## The slot
///
/// `{value}` — spelled out, because a journal is markdown and markdown has
/// opinions about punctuation. A bare `*` would read as emphasis half the time
/// it was written: `**Mood:** *` is a bold label and one slot, `*rough day*` is
/// an italic phrase and no slot at all, and no rule that told those apart could
/// be explained in a sentence. A word in braces means one thing wherever it
/// stands, and it is the syntax the templates already use.
///
/// Spaces and capitals inside the braces are allowed, as they are in a
/// placeholder's own — `{ value }` and `{Value}` are the same slot. Every slot
/// in the pattern is filled, because a pattern that names the answer twice
/// means it twice. And `\{value}` is the escape, for writing about one.
public struct AnswerFormat: Equatable, Sendable {
    /// What stands where the answer goes, as a template writes it.
    public static let slot = "{value}"

    /// The name inside the braces, matched the way a placeholder's own name is:
    /// lower-cased, so the capitals somebody typed do not decide anything.
    private static let name = "value"

    /// The pattern as it will be written, with its own surrounding whitespace
    /// trimmed off — `{{mood: Woke up feeling {value} }}` and
    /// `{{mood:Woke up feeling {value}}}` are the same sentence, and the braces
    /// are not where anybody indents a line.
    public let pattern: String

    /// A format, or `nil` for a pattern with nowhere to put the answer.
    ///
    /// Failable rather than forgiving, and this is what keeps the feature from
    /// eating answers: a pattern with no slot in it — `{{mood:Woke up feeling}}`,
    /// or an empty `{{mood:}}` — cannot say where a rating goes, so the token
    /// falls back to its default and the answer is still recorded. Writing the
    /// pattern verbatim instead would throw away the very thing the user had
    /// just been asked for, which is worse than ignoring words they can see are
    /// missing something.
    public init?(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !AnswerFormat.slots(in: trimmed).isEmpty else { return nil }
        self.pattern = trimmed
    }

    /// For the defaults, which are written in this module and known to have a
    /// slot — `InteractivePlaceholderFormatTests` holds them to it.
    init(unchecked pattern: String) {
        self.pattern = pattern
    }

    /// The pattern with the answer in every slot.
    public func filled(with answer: String) -> String {
        var written = ""
        var index = pattern.startIndex

        for slot in AnswerFormat.slots(in: pattern) {
            written += pattern[index..<slot.lowerBound]
            written += answer
            index = slot.upperBound
        }
        written += pattern[index...]
        return written
    }

    /// Where the answer goes, in order and never overlapping.
    ///
    /// The one reading of the pattern, so that a pattern this finds nothing in
    /// is exactly a pattern ``init(_:)`` refuses — a format that accepted a
    /// slot it then could not fill would be a sentence that came out unchanged.
    private static func slots(in pattern: String) -> [Range<String.Index>] {
        var slots: [Range<String.Index>] = []
        var index = pattern.startIndex

        while index < pattern.endIndex {
            // A backslash takes the next character with it, so `\{value}` is a
            // slot being written about rather than one to fill. It stays
            // escaped in the file, which is how it goes on being one.
            if pattern[index] == "\\" {
                index = pattern.index(after: index)
                if index < pattern.endIndex { index = pattern.index(after: index) }
                continue
            }
            if let slot = slot(in: pattern, at: index) {
                slots.append(slot)
                index = slot.upperBound
                continue
            }
            index = pattern.index(after: index)
        }
        return slots
    }

    /// One `{value}` starting here, or `nil` for a brace that opens something
    /// else — which the caller then treats as ordinary text and retries a
    /// character later, exactly as both of the token scans do.
    private static func slot(
        in pattern: String,
        at start: String.Index
    ) -> Range<String.Index>? {
        guard pattern[start] == "{" else { return nil }
        var index = pattern.index(after: start)

        func skipSpaces() {
            while index < pattern.endIndex, PlaceholderSyntax.isSpace(pattern[index]) {
                index = pattern.index(after: index)
            }
        }

        skipSpaces()
        let nameStart = index
        while index < pattern.endIndex, PlaceholderSyntax.isNameCharacter(pattern[index]) {
            index = pattern.index(after: index)
        }
        guard pattern[nameStart..<index].lowercased() == AnswerFormat.name else { return nil }

        skipSpaces()
        guard index < pattern.endIndex, pattern[index] == "}" else { return nil }
        return start..<pattern.index(after: index)
    }
}
