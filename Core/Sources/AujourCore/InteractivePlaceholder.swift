import Foundation

/// A placeholder the user answers rather than one the app resolves: a
/// `{{name}}` token that stays literal text in the file until it is answered,
/// and that the editor stands a widget in front of while it waits.
///
/// The third kind in the taxonomy, and the only one the file carries past the
/// spawn. A core placeholder is text by the time anybody reads the day, and so
/// is a data one — both are questions the device can answer on its own.
/// {{mood}} is not: nobody but the person writing knows, and they are not
/// asked at the moment a day is spawned. So the token is left where it stands,
/// and answering it rewrites those characters as plain markdown.
///
/// ## Why the token is the record
///
/// Because the folder is the journal (ADR 0001). An unanswered `{{mood}}` is
/// eight characters of literal text: harmless in Obsidian, untouched by every
/// tool that is not Aujour, and still there when Aujour opens the day again
/// next week — at which point it is a widget again, from the text alone.
/// Nothing anywhere lists which placeholders are outstanding, because there is
/// nothing to list: the token *is* the outstanding question, and answering it
/// is the same edit a hand could have made.
///
/// ## Registering one
///
/// Add a case. Everything the machinery does is done by name and knows nothing
/// else about it — the spawn passes the token through
/// (``SpawnContext/interactivePlaceholders``), the editor finds it in the text
/// (``EntryMarkdown/interactivePlaceholders(in:)``), stands a widget over it
/// (``DrawnElements``), and rewrites it once it is answered
/// (``EntryMarkdown/answering(_:in:with:)``).
///
/// What a case cannot say on its own is what needs a screen: what the widget
/// looks like, and what answering it asks. Both are the app's, and both are
/// `switch`es over this enum — so a new case does not compile until it has
/// been given them.
public enum InteractivePlaceholder: String, CaseIterable, Sendable {
    case mood
    case location

    /// The set ``SpawnContext/interactivePlaceholders`` defaults to.
    public static let registeredNames: Set<String> = Set(allCases.map(\.rawValue))
}

extension InteractivePlaceholder {
    /// One placeholder's token, found in an Entry's own text.
    public struct Token: Equatable, Sendable {
        public let placeholder: InteractivePlaceholder

        /// The whole token, braces and all, in the source's own UTF-16
        /// offsets — because the whole of it is what a widget stands in front
        /// of and what an answer takes the place of.
        public let range: NSRange

        /// Made outside Core by the editor, which reads a token's range back
        /// off the drawing standing over it and asks for it to be answered.
        public init(placeholder: InteractivePlaceholder, range: NSRange) {
            self.placeholder = placeholder
            self.range = range
        }
    }
}

// MARK: - Finding them

extension EntryMarkdown {
    /// Every registered interactive placeholder standing in the lines that
    /// were read, in order.
    ///
    /// Answers for whatever was read — the whole Entry, or the one paragraph a
    /// keystroke landed in — and answers in the whole source's coordinates,
    /// so a paragraph read on its own means what reading all of it would have
    /// meant.
    ///
    /// A token is read one line at a time, like everything else here: braces
    /// opened on one line and closed on the next are two lines of ordinary
    /// text, and not a token that would be found or missed depending on how
    /// much of the day the editor happened to re-read.
    ///
    /// Only the bare `{{name}}` shape, with or without spaces inside the
    /// braces — the same shapes a spawn passes through untouched
    /// (`InteractivePlaceholderTokenTests`). An offset or a `:FORMAT` belongs
    /// to {{date}} and {{time}}, which are resolved when the Entry is spawned
    /// and are never a widget.
    ///
    /// - Parameter source: the text this was read from, which is where the
    ///   names are spelled out.
    public func interactivePlaceholders(in source: String) -> [InteractivePlaceholder.Token] {
        guard !lines.isEmpty else { return [] }
        let units = Array(source.utf16)
        var tokens: [InteractivePlaceholder.Token] = []

        for line in lines {
            let notWords = InteractivePlaceholder.notWords(of: line.inlines)
            var index = line.content.location
            let end = min(line.content.upperBound, units.count)

            while index < end {
                guard
                    let token = InteractivePlaceholder.token(in: units, at: index, notBeyond: end)
                else {
                    index += 1
                    continue
                }
                if !notWords.contains(where: { NSIntersectionRange($0, token.range).length > 0 })
                {
                    tokens.append(token)
                }
                index = token.range.upperBound
            }
        }
        return tokens
    }

    /// The token at this index, or `nil` for an index that is in none.
    ///
    /// `index` is anywhere in the token, because a widget is drawn over all of
    /// it and there is no useful distinction between the characters a finger
    /// might land on.
    public func interactivePlaceholder(
        at index: Int,
        in source: String
    ) -> InteractivePlaceholder.Token? {
        interactivePlaceholders(in: source).first { NSLocationInRange(index, $0.range) }
    }
}

// MARK: - Answering one

extension EntryMarkdown {
    /// The edit that answers a placeholder's token, or `nil` when that is not
    /// where the token is any more.
    ///
    /// What answering a widget does, and the whole of it: the token's own
    /// characters are replaced by the words the widget handed over, and the
    /// Entry is plain markdown before and after — the file a widget answered
    /// and the file a hand typed are the same file (ADR 0001). Nothing is
    /// reformatted, nothing else in the day moves, and there is no record kept
    /// anywhere that this line was once a question.
    ///
    /// The answer goes in exactly as it was handed over. What a placeholder
    /// says once it is answered — "Today's mood: 4/5" (``MoodRating``), a
    /// place name — is that placeholder's own to word, and this is the part
    /// that is the same for all of them.
    ///
    /// - Parameters:
    ///   - asked: the token the user was answering, as it was when they were
    ///     asked. Read again here rather than trusted, because a sheet is open
    ///     while the Entry goes on living: a version arriving from another
    ///     device can move the text under it, and an answer must never land on
    ///     characters nobody was asked about. Its range is where to look and
    ///     its placeholder is what has to be found there.
    ///   - source: the text this was read from.
    ///   - answer: what to write in its place. An answer with no words in it
    ///     is not an answer, and leaves the token where it is — a widget
    ///     nobody filled in is a question still waiting.
    public func answering(
        _ asked: InteractivePlaceholder.Token,
        in source: String,
        with answer: String
    ) -> MarkdownEdit? {
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let token = interactivePlaceholder(at: asked.range.location, in: source),
            token.placeholder == asked.placeholder
        else { return nil }

        // No opinion about the cursor, for the same reason ticking a box has
        // none: the user was tapping a widget, not writing at it, and a caret
        // that jumped to the answer would leave the sentence they were in.
        return MarkdownEdit(range: token.range, replacement: answer)
    }
}

// MARK: - Reading the token

extension InteractivePlaceholder {
    private enum Unit {
        static let openBrace: UInt16 = 0x7B
        static let closeBrace: UInt16 = 0x7D
    }

    /// Reads one `{{name}}` starting at `start`, or `nil` for braces that are
    /// not one — which the caller then treats as ordinary text and retries a
    /// character later, exactly as the Content Template's own scan does.
    fileprivate static func token(
        in units: [UInt16],
        at start: Int,
        notBeyond end: Int
    ) -> Token? {
        guard start + 1 < end,
            units[start] == Unit.openBrace, units[start + 1] == Unit.openBrace
        else { return nil }

        var index = skippingSpaces(units, from: start + 2, to: end)
        let nameStart = index
        while index < end, isNameUnit(units[index]) { index += 1 }
        guard index > nameStart else { return nil }
        let name = String(decoding: units[nameStart..<index], as: UTF16.self).lowercased()

        index = skippingSpaces(units, from: index, to: end)
        guard index + 1 < end,
            units[index] == Unit.closeBrace, units[index + 1] == Unit.closeBrace,
            // Registered or not is the whole of what makes a token a widget:
            // {{weather}} is a placeholder nobody has written yet, and until
            // somebody does it is words like any other (v1 decisions).
            let placeholder = InteractivePlaceholder(rawValue: name)
        else { return nil }

        return Token(placeholder: placeholder, range: NSRange(start..<(index + 2)))
    }

    /// One UTF-16 unit as the shared rules read it, or `nil` for half of a
    /// character written as a surrogate pair — which no placeholder's name is,
    /// registered or not.
    private static func character(_ unit: UInt16) -> Character? {
        Unicode.Scalar(unit).map(Character.init)
    }

    private static func isNameUnit(_ unit: UInt16) -> Bool {
        character(unit).map(PlaceholderSyntax.isNameCharacter) ?? false
    }

    private static func skippingSpaces(_ units: [UInt16], from index: Int, to end: Int) -> Int {
        var cursor = index
        while cursor < end, character(units[cursor]).map(PlaceholderSyntax.isSpace) == true {
            cursor += 1
        }
        return cursor
    }

    /// The stretches of a line that are not words: a code span, and the
    /// address of a link or an embed.
    ///
    /// Where a token there is part of how something else is spelled rather
    /// than a question in a sentence. `{{mood}}` in backticks is the token
    /// being talked about — a journal is somewhere somebody writes about their
    /// journal — and `[home]({{location}})` is an address, which live preview
    /// does not even draw while the cursor is away from it.
    ///
    /// A token in a link's *words* is words, and stays a widget: answering it
    /// writes into the text of the link, which is where somebody put it.
    fileprivate static func notWords(of inlines: [MarkdownInline]) -> [NSRange] {
        var spans: [NSRange] = []
        for inline in inlines {
            if inline.style == .code {
                spans.append(inline.range)
                continue
            }
            if inline.destination.length > 0 {
                spans.append(inline.destination)
            }
            spans.append(contentsOf: notWords(of: inline.inlines))
        }
        return spans
    }
}

/// How a `{{name}}` token is spelled, in the one place both of its readers
/// agree about.
///
/// It is read twice and cannot be read two ways. ``ContentTemplate`` reads a
/// template at spawn and decides what passes through as literal text;
/// ``EntryMarkdown/interactivePlaceholders(in:)`` reads an Entry afterwards
/// and decides what is a widget. A shape one accepts and the other does not is
/// a token that survives the spawn and is never seen again — the round trip
/// broken by a tab.
///
/// The scans themselves are deliberately still two: one walks characters and
/// the other UTF-16 units, because the second has to answer in the offsets the
/// editor addresses text by. What must not differ is what counts as a name and
/// what counts as space, which is here.
enum PlaceholderSyntax {
    /// A hyphen is deliberately not a name character: it is how an offset
    /// starts, and `{{date-1d}}` has to read as "date, minus one day".
    static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// The whitespace allowed inside the braces, as in `{{ date }}`.
    static func isSpace(_ character: Character) -> Bool {
        character.isWhitespace
    }
}
