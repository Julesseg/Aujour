import AujourCore
import Foundation
import Testing
import UIKit

@testable import Aujour

// The editor's half of styled source mode. What a stretch of markdown *is*
// belongs to `EntryMarkdown` and is tested to death in Core; what is left is
// the part that needs a font to exist at all — that a heading really comes out
// larger, that the hashes that made it one are still there and still
// selectable, and that all of this costs one paragraph rather than the whole
// day's writing.
//
// Here rather than in the UI suite because none of it is about a screen: a
// text storage is an object with attributes in it, and a test that had to
// photograph an iPhone to see a bold word would be a slower test proving less.

@MainActor
@Suite("Markdown, styled where it is written")
struct MarkdownTextStorageTests {
    private let styling = MarkdownStyling()

    private func storage(holding source: String) -> MarkdownTextStorage {
        let storage = MarkdownTextStorage(styling: styling)
        storage.setSource(source)
        return storage
    }

    private func font(in storage: MarkdownTextStorage, at location: Int) throws -> UIFont {
        try #require(storage.attributes(at: location, effectiveRange: nil)[.font] as? UIFont)
    }

    private func colour(in storage: MarkdownTextStorage, at location: Int) throws -> UIColor {
        try #require(
            storage.attributes(at: location, effectiveRange: nil)[.foregroundColor] as? UIColor
        )
    }

    private func paragraph(
        in storage: MarkdownTextStorage,
        at location: Int
    ) throws -> NSParagraphStyle {
        try #require(
            storage.attributes(at: location, effectiveRange: nil)[.paragraphStyle]
                as? NSParagraphStyle
        )
    }

    private func isBold(_ font: UIFont) -> Bool {
        font.fontDescriptor.symbolicTraits.contains(.traitBold)
    }

    private func isItalic(_ font: UIFont) -> Bool {
        font.fontDescriptor.symbolicTraits.contains(.traitItalic)
    }

    // The promise the whole app rests on: an Entry is a plain markdown file
    // (ADR 0001), so the editor may add attributes to characters and may not
    // add characters.
    @Test("styling changes how the text is drawn and never what it says")
    func theTextIsUntouched() {
        let entry = """
            # Sunday 1 March

            Woke late, and *stayed* late.

            - milk
            - **bread**

            > Someone said something worth keeping.
            """
        let storage = storage(holding: entry)
        #expect(storage.string == entry)

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Before it: ")
        #expect(storage.string == "Before it: " + entry)
    }

    @Test("a heading is larger and bolder than the words under it")
    func headingsAreDrawnAsHeadings() throws {
        let storage = storage(holding: "# Sunday\n\nWoke late.")
        let heading = try font(in: storage, at: 2)
        let words = try font(in: storage, at: 10)

        #expect(heading.pointSize > words.pointSize)
        #expect(isBold(heading))
        #expect(!isBold(words))
    }

    @Test("deeper headings are smaller, and none of them smaller than the words")
    func headingLevels() throws {
        var previous = CGFloat.greatestFiniteMagnitude
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let storage = storage(holding: "\(hashes) Sunday")
            let size = try font(in: storage, at: level + 1).pointSize
            #expect(size <= previous, "level \(level) came out larger than level \(level - 1)")
            previous = size
        }
        #expect(previous >= styling.body.pointSize)
    }

    // Visible, quiet, and above all still there: a `#` the user cannot see is
    // one they cannot delete, and the file has one in it either way.
    @Test("the characters that make a heading are drawn more quietly than its words")
    func syntaxIsVisibleAndQuiet() throws {
        let storage = storage(holding: "## Morning")
        let hash = try colour(in: storage, at: 0)
        let word = try colour(in: storage, at: 3)

        #expect(storage.string.hasPrefix("## "))
        #expect(hash != word)
        #expect(hash == styling.syntax)
    }

    @Test("two stars make the words between them bold, and stay stars")
    func strongEmphasis() throws {
        let storage = storage(holding: "A **loud** word")
        let loud = try font(in: storage, at: 4)
        let plain = try font(in: storage, at: 0)
        let star = try colour(in: storage, at: 2)

        #expect(isBold(loud))
        #expect(!isBold(plain))
        #expect(star == styling.syntax)
    }

    @Test("one star makes them italic")
    func emphasis() throws {
        let storage = storage(holding: "A *soft* word")
        #expect(isItalic(try font(in: storage, at: 3)))
    }

    // Nothing anywhere names "italic, bold, heading-sized": each span adds
    // what it means to whatever it lands on.
    @Test("emphasis inside a heading is emphatic and still a heading")
    func stylesStack() throws {
        let storage = storage(holding: "# A *soft* heading")
        let emphasised = try font(in: storage, at: 5)

        #expect(isItalic(emphasised))
        #expect(isBold(emphasised))
        #expect(emphasised.pointSize > styling.body.pointSize)
    }

    @Test("code is set in a face where every character is the same width")
    func codeSpans() throws {
        let storage = storage(holding: "Run `swift test` again")
        let code = try font(in: storage, at: 6)
        let narrow = ("i" as NSString).size(withAttributes: [.font: code]).width
        let wide = ("m" as NSString).size(withAttributes: [.font: code]).width

        #expect(abs(narrow - wide) < 0.01, "expected a monospaced face, got \(code.fontName)")
    }

    @Test("a wrapped list item lines up under its own words, not under its bullet")
    func listsHang() throws {
        let item = storage(holding: "- milk, and quite a lot of other things besides")
        let style = try paragraph(in: item, at: 4)
        #expect(style.headIndent > 0)
        #expect(style.firstLineHeadIndent == 0)

        let nested = storage(holding: "    - milk")
        let nestedStyle = try paragraph(in: nested, at: 8)
        #expect(nestedStyle.firstLineHeadIndent > 0)
        #expect(nestedStyle.headIndent > nestedStyle.firstLineHeadIndent)
    }

    @Test("a quote is drawn as somebody else's words")
    func quotes() throws {
        let storage = storage(holding: "> Someone said this")
        #expect(try colour(in: storage, at: 4) == styling.quoted)
    }

    @Test("what is typed is styled as it is typed")
    func editingRestyles() throws {
        let storage = storage(holding: "Sunday")
        #expect(!isBold(try font(in: storage, at: 0)))

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# ")
        let heading = try font(in: storage, at: 2)

        #expect(storage.string == "# Sunday")
        #expect(isBold(heading))
        #expect(heading.pointSize > styling.body.pointSize)
    }

    @Test("a line that stops being a heading stops being drawn as one")
    func editingUnstyles() throws {
        let storage = storage(holding: "# Sunday")
        storage.replaceCharacters(in: NSRange(location: 0, length: 2), with: "")

        #expect(storage.string == "Sunday")
        #expect(try font(in: storage, at: 0).pointSize == styling.body.pointSize)
    }

    // The half below the break is in a paragraph the edit never touched, and
    // it is exactly the half that stops being a heading.
    @Test("a heading split in two leaves a heading and a line of ordinary words")
    func splittingALine() throws {
        let storage = storage(holding: "# Sunday and more")
        storage.replaceCharacters(in: NSRange(location: 8, length: 0), with: "\n")
        let below = try font(in: storage, at: 12)

        #expect(storage.string == "# Sunday\n and more")
        #expect(isBold(try font(in: storage, at: 2)))
        #expect(!isBold(below))
        #expect(below.pointSize == styling.body.pointSize)
    }

    // The claim that makes this editor usable on a long day, and the one thing
    // the styling itself cannot show: it comes out the same either way, so
    // what is measured here is the work, not the result.
    @Test("a keystroke costs the paragraph it landed in, whatever the entry weighs")
    func typingCostsOneParagraph() throws {
        let entry = (1...500)
            .map { "Paragraph \($0), with *some* emphasis and a few plain words in it." }
            .joined(separator: "\n\n")
        let storage = storage(holding: entry)
        #expect(storage.length > 20_000)

        let middle = (entry as NSString).range(of: "Paragraph 250,")
        storage.replaceCharacters(in: NSRange(location: middle.location, length: 0), with: "**")

        let restyled = try #require(storage.restyledRanges.first)
        #expect(storage.restyledRanges.count == 1)
        #expect(restyled.location <= middle.location)
        #expect(restyled.length < 200, "restyled \(restyled.length) characters for two")
        #expect(restyled.upperBound <= storage.length)
    }

    @Test("opening a day styles all of it")
    func openingADayStylesEverything() throws {
        let storage = storage(holding: "Woke late.")
        storage.setSource("# Sunday\n\nWoke late.")

        #expect(storage.restyledRanges == [NSRange(location: 0, length: storage.length)])
        #expect(isBold(try font(in: storage, at: 2)))
    }

    // The caret sits after the last word of a heading too, and a caret at
    // body height there reads as a heading that has already ended.
    @Test("a line's break is drawn as part of the line, not as what follows it")
    func lineBreaksBelongToTheirLine() throws {
        let storage = storage(holding: "# Sunday\nWoke late.")
        let heading = try font(in: storage, at: 2)
        let breakAfterIt = try font(in: storage, at: 8)

        #expect(breakAfterIt == heading)
    }

    // Dynamic Type, and later the editor font setting: every font in the
    // editor is derived from one, so moving it moves all of them — and
    // nothing else about the styling moves with it.
    @Test("a larger reading size makes every shape larger")
    func stylingFollowsTheBodyFont() throws {
        let storage = storage(holding: "# Sunday")
        let before = try font(in: storage, at: 2).pointSize

        storage.styling = storage.styling.with(body: styling.body.withSize(60))

        #expect(try font(in: storage, at: 2).pointSize > before)
        #expect(try colour(in: storage, at: 0) == styling.syntax)
        #expect(storage.string == "# Sunday")
    }
}
