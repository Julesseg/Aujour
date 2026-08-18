import Foundation
import Testing

@testable import AujourCore

// The general mechanism behind {{mood}} and {{location}}: a token that stays
// literal text in the file until somebody answers it. Which stretches of an
// Entry are one, and what answering one writes, is decided here from the text
// alone — what the widget looks like and what it asks needs a screen and is
// the app's.

@Suite("Finding an interactive placeholder in an entry")
struct InteractivePlaceholderTokenTests {
    private func tokens(in source: String) -> [InteractivePlaceholder.Token] {
        EntryMarkdown(source).interactivePlaceholders(in: source)
    }

    /// What each token found covers, as the characters it covers.
    private func covered(in source: String) -> [String] {
        let text = source as NSString
        return tokens(in: source).map { text.substring(with: $0.range) }
    }

    @Test("a registered placeholder is a token wherever it stands")
    func registeredNames() {
        let entry = "Woke late. {{mood}}\n\n{{location}}"
        #expect(tokens(in: entry).map(\.placeholder) == [.mood, .location])
        #expect(covered(in: entry) == ["{{mood}}", "{{location}}"])
    }

    // The spawn passes an interactive placeholder through as the literal text
    // it was written as, and the editor has to find that same text again — so
    // the two read the token the same way, spelling for spelling.
    @Test("the spellings a spawn passes through are the ones the editor finds")
    func theSameSpellingsAsTheSpawn() {
        for placeholder in InteractivePlaceholder.allCases {
            let name = placeholder.rawValue
            let spellings = [
                "{{\(name)}}", "{{ \(name) }}", "{{\(name.uppercased())}}", "{{\t\(name)\t}}",
            ]
            for written in spellings {
                let spawned = ContentTemplate(written).render(
                    at: SpawnContext(
                        day: JournalDay(year: 2026, month: 3, day: 1),
                        instant: instant(2026, 3, 1, 9, in: paris),
                        title: "2026-03-01",
                        timeZone: paris
                    )
                )
                #expect(spawned == written, "the spawn did not pass \(written) through")
                #expect(
                    tokens(in: spawned).map(\.placeholder) == [placeholder],
                    "the editor did not find \(written)"
                )
            }
        }
    }

    @Test("a placeholder nobody registered is words like any other")
    func unregisteredNames() {
        #expect(tokens(in: "{{weather}}").isEmpty)
        #expect(tokens(in: "{{date}} {{title}} {{events}}").isEmpty)
    }

    // Only the bare shape. An offset and a `:FORMAT` belong to {{date}} and
    // {{time}}, which are resolved at the spawn and are never a widget — and
    // a token carrying one is not a placeholder this can answer.
    @Test("braces that are not a bare token are not a widget")
    func malformedTokens() {
        #expect(tokens(in: "{{mood").isEmpty)
        #expect(tokens(in: "{{}}").isEmpty)
        #expect(tokens(in: "{mood}").isEmpty)
        #expect(tokens(in: "{{mood:HH}}").isEmpty)
        #expect(tokens(in: "{{mood+1d}}").isEmpty)
        #expect(tokens(in: "{{mood location}}").isEmpty)
    }

    // A journal is somewhere somebody writes about their journal: `{{mood}}`
    // in backticks is the token being talked about, not one being asked.
    @Test("a token inside a code span is code")
    func tokensInCode() {
        #expect(tokens(in: "Put `{{mood}}` in the template.").isEmpty)
        #expect(covered(in: "`{{mood}}` and {{mood}}") == ["{{mood}}"])
    }

    // An address is not words, and live preview does not even draw one while
    // the cursor is away from it — a widget standing inside an invisible URL
    // would be a question the user could answer into their own link.
    @Test("a token inside an address is part of the address")
    func tokensInAddresses() {
        #expect(tokens(in: "[home]({{location}})").isEmpty)
        #expect(tokens(in: "![a]({{location}}.jpg)").isEmpty)
        // The words of a link are words, and a question written among them is
        // one somebody asked there.
        #expect(covered(in: "[{{mood}}](home.md)") == ["{{mood}}"])
    }

    // The editor re-reads the paragraph a keystroke landed in and asks this of
    // the stretch it read, so the answer is about that paragraph and comes
    // back in the whole Entry's coordinates.
    @Test("a reading of one paragraph answers for that paragraph")
    func partialReadings() {
        let entry = "{{mood}}\n\nWoke late.\n\n{{location}}"
        let paragraph = EntryMarkdown(entry, around: NSRange(location: 24, length: 0))
        let found = paragraph.interactivePlaceholders(in: entry)

        #expect(found.map(\.placeholder) == [.location])
        #expect(found.map(\.range) == [NSRange(location: 22, length: 12)])
    }

    @Test("an entry with no tokens in it has none")
    func plainWords() {
        #expect(tokens(in: "Woke late, and stayed late.").isEmpty)
        #expect(tokens(in: "").isEmpty)
    }
}

@Suite("Answering an interactive placeholder")
struct AnsweringAPlaceholderTests {
    /// The token a widget over `{{mood}}` at the start of an Entry stands on.
    private let mood = InteractivePlaceholder.Token(
        placeholder: .mood, range: NSRange(location: 0, length: 8)
    )

    private func answered(
        _ source: String,
        _ placeholder: InteractivePlaceholder,
        at index: Int,
        with answer: String
    ) -> String? {
        let asked = InteractivePlaceholder.Token(
            placeholder: placeholder, range: NSRange(location: index, length: 0)
        )
        guard let edit = EntryMarkdown(source).answering(asked, in: source, with: answer)
        else { return nil }
        let rewritten = NSMutableString(string: source)
        rewritten.replaceCharacters(in: edit.range, with: edit.replacement)
        return rewritten as String
    }

    @Test("answering writes plain text where the token was, and nothing else")
    func answeringInPlace() {
        let entry = "# Sunday\n\n{{mood}}\n\nWalked home.\n"
        #expect(
            answered(entry, .mood, at: 10, with: "Today's mood: 4/5")
                == "# Sunday\n\nToday's mood: 4/5\n\nWalked home.\n"
        )
    }

    @Test("the whole token goes, braces and all")
    func theEditIsTheToken() {
        let edit = EntryMarkdown("{{mood}}").answering(mood, in: "{{mood}}", with: "Good")
        #expect(edit == MarkdownEdit(range: NSRange(location: 0, length: 8), replacement: "Good"))
    }

    // A widget is drawn over the whole token, so a finger on it can land on
    // any character of it.
    @Test("anywhere in the token answers it")
    func anywhereInTheToken() {
        for index in 11...18 {
            #expect(
                answered("Woke late. {{mood}}", .mood, at: index, with: "Good")
                    == "Woke late. Good"
            )
        }
    }

    // The sheet is open while the Entry goes on living: iCloud can bring a
    // version from another device, and the token the widget was standing over
    // may not be there any more.
    @Test("a token that is not the one asked about is left alone")
    func theWrongToken() {
        #expect(answered("{{location}}", .mood, at: 0, with: "Good") == nil)
        #expect(answered("Woke late.", .mood, at: 3, with: "Good") == nil)
        #expect(answered("{{mood}}", .mood, at: 40, with: "Good") == nil)
        #expect(answered("", .mood, at: 0, with: "Good") == nil)
    }

    @Test("an answer with nothing in it is not an answer")
    func emptyAnswers() {
        #expect(answered("{{mood}}", .mood, at: 0, with: "") == nil)
        #expect(answered("{{mood}}", .mood, at: 0, with: "  \n ") == nil)
    }

    // Where the user was writing is not something a widget somewhere else in
    // the day has an opinion about — the same rule a ticked box follows.
    @Test("answering says nothing about where the cursor goes")
    func noOpinionOnTheCursor() {
        let edit = EntryMarkdown("{{mood}}").answering(mood, in: "{{mood}}", with: "Good")
        #expect(edit?.selection == nil)
    }

    @Test("the entry either side of the token is untouched, byte for byte")
    func nothingElseMoves() {
        let entry = """
            # Sunday

            {{mood}}

            - [x] **bread**, still warm
            """
        let after = answered(entry, .mood, at: 10, with: "Slept badly, better by noon")
        #expect(
            after == entry.replacingOccurrences(
                of: "{{mood}}", with: "Slept badly, better by noon"
            )
        )
    }
}
