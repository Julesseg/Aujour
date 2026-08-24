import AujourCore
import Foundation
import Testing
import UIKit

@testable import Aujour

// The editor's half of interactive placeholders. Which stretches of an Entry
// are an unanswered question, and what answering one writes, is decided in
// Core and tested there against the text it came from; what is left is the
// part that only exists once there is a font, a layout and a finger — that a
// widget really takes a widget's room on the line while its token takes none,
// that a tap on it asks the question, and that the answer reaches the file as
// plain markdown while a question nobody answered leaves the token exactly
// where it stood.
//
// Headless: a text storage with a layout manager attached is enough to ask how
// big anything came out, and the sheet the app would put up is stood in for by
// the closure it would have called (`OpenEditor.asked`).

@MainActor
@Suite("Widgets in place of an entry's unanswered placeholders")
struct PlaceholderWidgetTests {
    private let styling = MarkdownStyling()

    private func storage(holding source: String, cursor: NSRange? = nil) -> MarkdownTextStorage {
        let storage = MarkdownTextStorage(styling: styling)
        storage.setSource(source)
        storage.cursor = cursor
        return storage
    }

    /// What the storage marked as drawn over, as the characters each drawing
    /// stands in front of and which placeholder it asks.
    private func widgets(
        in storage: MarkdownTextStorage
    ) -> [(text: String, placeholder: InteractivePlaceholder)] {
        var found: [(String, InteractivePlaceholder)] = []
        storage.enumerateAttribute(
            .drawnMarkdown,
            in: NSRange(location: 0, length: storage.length)
        ) { value, _, _ in
            guard let drawn = value as? DrawnMarkdown,
                case .widget(let placeholder, _) = drawn.kind
            else { return }
            found.append(((storage.string as NSString).substring(with: drawn.text), placeholder))
        }
        return found
    }

    // MARK: - What is drawn

    @Test("an unanswered placeholder is drawn as its own widget")
    func placeholdersBecomeWidgets() {
        let entry = storage(holding: "{{mood}}\n\nWalked home from {{location}}.")
        let drawn = widgets(in: entry)

        #expect(drawn.map(\.text) == ["{{mood}}", "{{location}}"])
        #expect(drawn.map(\.placeholder) == [.mood, .location])
    }

    @Test("the widget gives way to its own markdown at the cursor")
    func aPlaceholderAtTheCursor() {
        let entry = storage(holding: "{{mood}}", cursor: NSRange(location: 4, length: 0))
        #expect(widgets(in: entry).isEmpty)

        entry.cursor = nil
        #expect(widgets(in: entry).map(\.text) == ["{{mood}}"])
    }

    // The whole point of the attribute, and the only test that can see it: the
    // token's own characters take up no room at all, and the widget takes
    // exactly the room it asked for in their place.
    @Test("the widget takes a widget's room, and the token under it takes none")
    func aWidgetIsLaidOut() {
        let token = NSRange(location: 0, length: 8)
        let drawn = laidOut("{{mood}} — woke late", cursor: nil)
        let written = laidOut("{{mood}} — woke late", cursor: NSRange(location: 4, length: 0))

        let widget = try! #require(drawn.drawing(at: 0))
        let font = drawn.storage.font(at: 0)
        #expect(
            abs(drawn.width(of: token) - widget.size(in: font, fitting: 600).width) < 1,
            "the widget was not laid out at the size it asked for"
        )
        // And the line it is on is a line's height still: a question in the
        // middle of a paragraph is still a paragraph.
        #expect(abs(drawn.lineHeight(atCharacter: 0) - written.lineHeight(atCharacter: 0)) < 1)
    }

    // MARK: - A finger on one

    @Test("a tap on the widget asks the placeholder's question")
    func tappingAWidget() throws {
        let entry = editor(holding: "{{mood}}\nWalked home.\n")
        #expect(entry.coordinator.tapped(in: entry.textView, at: entry.firstBox))

        let asked = try #require(entry.asked)
        #expect(asked.placeholder == .mood)
        // Asking changes nothing: the token is still every character it was,
        // and nothing has been saved.
        #expect(entry.textView.text == "{{mood}}\nWalked home.\n")
        #expect(entry.written == nil)
    }

    @Test("answering writes plain markdown where the token was, and tells the entry")
    func answeringAWidget() throws {
        let entry = editor(holding: "{{mood}}\nWalked home.\n")
        entry.coordinator.tapped(in: entry.textView, at: entry.firstBox)
        // The sentence the rating widget hands over, asked for rather than
        // copied: what a mood is written down as is Core's, and this is the
        // test that it arrives in the file that way.
        try #require(entry.asked).answered(try #require(MoodRating(4)).answer)

        #expect(entry.textView.text == "Today's mood: 4/5\nWalked home.\n")
        #expect(entry.written == "Today's mood: 4/5\nWalked home.\n")
        // And there is nothing left to tap: the question was the token.
        #expect(widgets(in: entry.storage).isEmpty)
    }

    // A template may word the question itself, and then the sentence in the
    // file is the template's rather than the placeholder's default. The whole
    // token goes — format, braces and all — because the whole of it was the
    // question.
    @Test("a token that worded its own question is answered in those words")
    func answeringAFormattedWidget() throws {
        let entry = editor(holding: "{{mood:Woke up feeling {value}}}\nWalked home.\n")
        entry.coordinator.tapped(in: entry.textView, at: entry.firstBox)
        try #require(entry.asked).answered(try #require(MoodRating(4)).answer)

        #expect(entry.textView.text == "Woke up feeling 4/5\nWalked home.\n")
        #expect(entry.written == "Woke up feeling 4/5\nWalked home.\n")
        #expect(widgets(in: entry.storage).isEmpty)
    }

    // And it is a widget over all of it meanwhile: a format is part of the
    // question, not words standing beside one.
    @Test("the widget stands over the format too")
    func aFormattedTokenIsOneWidget() {
        let entry = storage(holding: "{{mood:Woke up feeling {value}}} — and better by noon")
        #expect(widgets(in: entry).map(\.text) == ["{{mood:Woke up feeling {value}}}"])
    }

    // A format is markdown the day has not written yet, so a template that
    // words its question in bold is still one question: the emphasis inside the
    // braces is styling nobody is meant to see until the answer is in the file.
    @Test("markdown inside a format does not break the widget in two")
    func aFormatCarryingMarkdown() throws {
        let token = "{{mood:**Mood:** {value}}}"
        let entry = editor(holding: "\(token)\nWalked home.\n")
        #expect(widgets(in: entry.storage).map(\.text) == [token])

        entry.coordinator.tapped(in: entry.textView, at: entry.firstBox)
        try #require(entry.asked).answered(try #require(MoodRating(4)).answer)

        #expect(entry.textView.text == "**Mood:** 4/5\nWalked home.\n")
    }

    // Cancelling is answering nothing, and a question nobody answered is still
    // a question — literal text in the file, and a widget again next time.
    @Test("a question nobody answers leaves the token where it stood")
    func cancellingAQuestion() throws {
        let entry = editor(holding: "{{mood}}\n")
        entry.coordinator.tapped(in: entry.textView, at: entry.firstBox)
        try #require(entry.asked).answered("   ")

        #expect(entry.textView.text == "{{mood}}\n")
        #expect(entry.written == nil)
        #expect(widgets(in: entry.storage).map(\.text) == ["{{mood}}"])
    }

    // The sheet is up for as long as somebody is answering it, and the Entry
    // goes on living underneath: a version arriving from another device
    // replaces the whole text, and the characters the widget stood over are
    // then somebody else's words.
    @Test("an answer that arrives after the day has moved on is not written")
    func answeringAnEntryThatMovedOn() throws {
        let entry = editor(holding: "{{mood}}\n")
        entry.coordinator.tapped(in: entry.textView, at: entry.firstBox)
        let asked = try #require(entry.asked)

        entry.storage.setSource("Walked home the long way.\n")
        asked.answered("4/5")

        #expect(entry.textView.text == "Walked home the long way.\n")
    }

    // An answer is an edit, and the day it is in is full of other edits.
    @Test("an answer can be undone, like any other edit")
    func undoingAnAnswer() throws {
        let entry = editor(holding: "{{mood}}\n")
        entry.coordinator.tapped(in: entry.textView, at: entry.firstBox)
        try #require(entry.asked).answered("4/5")
        #expect(entry.textView.text == "Today's mood: 4/5\n")

        let undo = try #require(entry.textView.undoManager)
        #expect(undo.canUndo)
        undo.undo()

        #expect(entry.textView.text == "{{mood}}\n")
        #expect(entry.written == "{{mood}}\n")
    }

    // A widget is answered from wherever the finger lands, which is not where
    // the user was writing — so the caret stays in the sentence it was in,
    // even though the answer is a different length from the token it replaced.
    @Test("answering leaves the caret in the words it was in")
    func theCaretStaysPut() throws {
        let entry = editor(holding: "{{mood}}\nWalked home.\n")
        // In the middle of "home", where somebody was writing.
        entry.cursor(at: 19)

        entry.coordinator.tapped(in: entry.textView, at: entry.firstBox)
        try #require(entry.asked).answered("4/5")

        let caret = entry.textView.selectedRange
        #expect((entry.textView.text as NSString).substring(to: caret.location).hasSuffix("hom"))
    }

    @Test("a tap on words is not a tap on a widget")
    func tappingBesideAWidget() {
        let entry = editor(holding: "{{mood}} woke late\n")
        var beside = entry.firstBox
        beside.x += 200

        #expect(!entry.coordinator.tapped(in: entry.textView, at: beside))
        #expect(entry.asked == nil)
        #expect(entry.written == nil)
    }

    // MARK: - Round-tripping

    // The named edge of the whole mechanism: nothing anywhere remembers that a
    // question was asked, so a token that comes back from the folder — the
    // day reopened, or an edit made in Obsidian arriving while it is open — is
    // a widget again from the text alone.
    @Test("a token that comes back from the folder is a widget again")
    func tokensThatComeBack() {
        let entry = storage(holding: "Walked home the long way.\n")
        #expect(widgets(in: entry).isEmpty)

        entry.setSource("Walked home the long way.\n\n{{location}}\n")
        #expect(widgets(in: entry).map(\.text) == ["{{location}}"])

        // And the file the folder holds is those characters, untouched: the
        // editor added nothing to the text to draw over it.
        #expect(entry.string == "Walked home the long way.\n\n{{location}}\n")
    }

    // MARK: - Laying one out

    private func editor(holding source: String) -> OpenEditor {
        OpenEditor(holding: source, styling: styling)
    }

    /// An Entry laid out by the editor's own layout manager and glyph
    /// delegate — the only way to ask how big anything actually came out.
    @MainActor
    private struct LaidOut {
        let layoutManager: NSLayoutManager
        let container: NSTextContainer
        /// Both held because a layout manager keeps neither its delegate nor
        /// its text storage alive.
        let storage: MarkdownTextStorage
        let glyphs: MarkdownGlyphs

        func drawing(at character: Int) -> DrawnMarkdown? {
            storage.attribute(.drawnMarkdown, at: character, effectiveRange: nil) as? DrawnMarkdown
        }

        func width(of characters: NSRange) -> CGFloat {
            let glyphs = layoutManager.glyphRange(
                forCharacterRange: characters, actualCharacterRange: nil
            )
            guard glyphs.length > 0 else { return 0 }
            return layoutManager.boundingRect(forGlyphRange: glyphs, in: container).width
        }

        func lineHeight(atCharacter character: Int) -> CGFloat {
            let glyph = layoutManager.glyphIndexForCharacter(at: character)
            return layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).height
        }
    }

    private func laidOut(_ source: String, cursor: NSRange?) -> LaidOut {
        let storage = MarkdownTextStorage(styling: styling)
        let layoutManager = MarkdownLayoutManager()
        let glyphs = MarkdownGlyphs()
        let container = NSTextContainer(
            size: CGSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        )

        layoutManager.delegate = glyphs
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        storage.setSource(source)
        storage.cursor = cursor
        layoutManager.ensureLayout(for: container)

        return LaidOut(
            layoutManager: layoutManager,
            container: container,
            storage: storage,
            glyphs: glyphs
        )
    }
}
