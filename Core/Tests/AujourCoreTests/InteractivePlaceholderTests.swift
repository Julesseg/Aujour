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
                "{{\(name):Woke up feeling {value}}}", "{{ \(name) : Woke up feeling {value} }}",
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

    // The other half of that agreement. A shape the editor will never find is
    // not one the spawn passes through either, or the file would keep a token
    // no widget ever stands over — literal `{{mood+1d}}` in somebody's journal
    // for good. An offset is the one such shape: it belongs to {{date}} and
    // {{time}}, and means nothing to a question the user answers.
    @Test("a shape the editor cannot find does not survive the spawn either")
    func theSpawnDropsWhatTheEditorCannotFind() {
        for placeholder in InteractivePlaceholder.allCases {
            let written = "{{\(placeholder.rawValue)+1d}}"
            let spawned = ContentTemplate(written).render(
                at: SpawnContext(
                    day: JournalDay(year: 2026, month: 3, day: 1),
                    instant: instant(2026, 3, 1, 9, in: paris),
                    title: "2026-03-01",
                    timeZone: paris
                )
            )
            #expect(spawned == "", "the spawn left \(written) in the entry")
            #expect(tokens(in: written).isEmpty)
        }
    }

    @Test("a placeholder nobody registered is words like any other")
    func unregisteredNames() {
        #expect(tokens(in: "{{weather}}").isEmpty)
        #expect(tokens(in: "{{date}} {{title}} {{events}}").isEmpty)
    }

    // An offset belongs to {{date}} and {{time}}, which are resolved at the
    // spawn and are never a widget — and a token carrying one is not a
    // placeholder this can answer.
    @Test("braces that are not a token are not a widget")
    func malformedTokens() {
        #expect(tokens(in: "{{mood").isEmpty)
        #expect(tokens(in: "{{}}").isEmpty)
        #expect(tokens(in: "{mood}").isEmpty)
        #expect(tokens(in: "{{mood+1d}}").isEmpty)
        #expect(tokens(in: "{{mood location}}").isEmpty)
        #expect(tokens(in: "{{mood:unclosed").isEmpty)
    }

    // A token may carry the words its answer is written in, and the whole of
    // it — format and braces — is what the widget stands over and what the
    // answer takes the place of.
    @Test("a token can carry the words its answer goes in")
    func tokensWithFormats() {
        let entry = "{{mood:Woke up feeling {value}}}"
        #expect(covered(in: entry) == [entry])
        #expect(tokens(in: entry).map(\.placeholder) == [.mood])
        #expect(tokens(in: entry).first?.format?.pattern == "Woke up feeling {value}")
    }

    // The slot has braces of its own, so a token that ends on one ends in three
    // of them. The braces a format opened are counted and closed, and the pair
    // that ends the token is the first one outside them — otherwise the token
    // would stop inside its own slot and the rest would be loose text.
    @Test("a format's own braces do not close the token")
    func formatsHoldingBraces() {
        #expect(
            covered(in: "{{mood:{value}}} then {{location:in {value}}}")
                == ["{{mood:{value}}}", "{{location:in {value}}}"]
        )
        // Braces around something that is not the slot are the format's too.
        #expect(
            tokens(in: "{{mood:{day} felt {value}}}").first?.format?.pattern
                == "{day} felt {value}"
        )
        // And a brace the format never closes is not a token at all.
        #expect(tokens(in: "{{mood:{value}").isEmpty)
    }

    // A format with nowhere to put the answer is no format at all, and the
    // token falls back to its default rather than to nothing — the widget is
    // still a widget and the answer is still recorded.
    @Test("a format with nowhere to put the answer is not one")
    func tokensWithUnusableFormats() {
        #expect(tokens(in: "{{mood:HH}}").map(\.placeholder) == [.mood])
        #expect(tokens(in: "{{mood:HH}}").first?.format == nil)
        #expect(tokens(in: "{{mood:}}").first?.format == nil)
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

    /// And over `{{location}}`, which is what the tests about the *mechanism*
    /// use: its default format is the answer and nothing else, so what those
    /// assert is where the edit lands rather than how a placeholder is worded.
    private let location = InteractivePlaceholder.Token(
        placeholder: .location, range: NSRange(location: 0, length: 12)
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
        let entry = "# Sunday\n\n{{location}}\n\nWalked home.\n"
        #expect(
            answered(entry, .location, at: 10, with: "Caf\u{e9} de Flore")
                == "# Sunday\n\nCaf\u{e9} de Flore\n\nWalked home.\n"
        )
    }

    @Test("the whole token goes, braces and all")
    func theEditIsTheToken() {
        let entry = "{{location}}"
        let edit = EntryMarkdown(entry).answering(location, in: entry, with: "Home")
        #expect(edit == MarkdownEdit(range: NSRange(location: 0, length: 12), replacement: "Home"))
    }

    // A widget is drawn over the whole token, so a finger on it can land on
    // any character of it.
    @Test("anywhere in the token answers it")
    func anywhereInTheToken() {
        for index in 11...22 {
            #expect(
                answered("Woke late. {{location}}", .location, at: index, with: "Home")
                    == "Woke late. Home"
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

    // MARK: - The words the answer goes in

    // The default is a format like any other, which is the whole of why there
    // is no second mechanism here: a bare token is one that did not word its
    // own question, so the placeholder words it.
    @Test("a bare token is written in its placeholder's own default")
    func theDefaultFormat() {
        #expect(answered("{{mood}}", .mood, at: 0, with: "4/5") == "Today's mood: 4/5")
        #expect(answered("{{location}}", .location, at: 0, with: "Home") == "Home")
    }

    // And a template that worded the question gets its own sentence back, with
    // the answer where it put the slot.
    @Test("a token carrying a format is written the template's way")
    func aFormatWordsTheAnswer() {
        #expect(
            answered("{{mood:The mood for today was {value}}}", .mood, at: 0, with: "4/5")
                == "The mood for today was 4/5"
        )
        let worded = "Wrote this in {{location:{value}, as ever}}."
        #expect(
            answered(worded, .location, at: 14, with: "Paris")
                == "Wrote this in Paris, as ever."
        )
    }

    // A format with no slot cannot say where the answer goes, so the token
    // falls back to its default rather than writing words with the rating
    // dropped out of them.
    @Test("a format with nowhere to put the answer falls back to the default")
    func anUnusableFormatFallsBack() {
        #expect(
            answered("{{mood:Woke up feeling}}", .mood, at: 0, with: "4/5")
                == "Today's mood: 4/5"
        )
    }

    // The sheet is open while the day goes on living, so the wording is read
    // off the token that is there when the answer arrives — not the one the
    // widget was standing over when it was tapped.
    @Test("the answer is worded by the token that is there now")
    func theWordingIsReadAgain() {
        let asked = InteractivePlaceholder.Token(
            placeholder: .mood,
            range: NSRange(location: 0, length: 8),
            format: AnswerFormat("Woke up feeling {value}")
        )
        let arrived = "{{mood:The mood for today was {value}}}"
        let edit = EntryMarkdown(arrived).answering(asked, in: arrived, with: "4/5")

        #expect(edit?.replacement == "The mood for today was 4/5")
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
        let edit = EntryMarkdown("{{mood}}").answering(mood, in: "{{mood}}", with: "4/5")
        #expect(edit?.selection == nil)
    }

    @Test("the entry either side of the token is untouched, byte for byte")
    func nothingElseMoves() {
        let entry = """
            # Sunday

            {{location}}

            - [x] **bread**, still warm
            """
        let after = answered(entry, .location, at: 10, with: "the long way home")
        #expect(
            after == entry.replacingOccurrences(
                of: "{{location}}", with: "the long way home"
            )
        )
    }
}

// The half of a placeholder that says how it is worded. Named in
// ``AnswerFormat``'s own documentation as what holds the defaults to their
// promise, because they are the one place an unchecked format is built.
@Suite("How a placeholder is worded when nobody worded it")
struct InteractivePlaceholderFormatTests {
    // A default with no slot in it would be a question that swallowed its
    // answer — the one failure the format rules exist to prevent, in the one
    // place those rules are skipped.
    @Test("every placeholder's default has somewhere to put the answer")
    func everyDefaultHasASlot() {
        for placeholder in InteractivePlaceholder.allCases {
            #expect(
                AnswerFormat(placeholder.defaultFormat.pattern) != nil,
                "\(placeholder.rawValue)'s default has nowhere to put an answer"
            )
        }
    }

    @Test("a mood says what it is, and a place speaks for itself")
    func theDefaults() {
        #expect(InteractivePlaceholder.mood.defaultFormat.pattern == "Today's mood: {value}")
        #expect(InteractivePlaceholder.location.defaultFormat.pattern == "{value}")
    }
}
