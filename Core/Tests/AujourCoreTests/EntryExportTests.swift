import Foundation
import Testing

@testable import AujourCore

// A day on its way out of the app: what it is called, what the text form of
// it says, and whether there is anything to send at all. None of that needs a
// page to be drawn on, which is why it is here — what a PDF *looks like* is
// the app's, and is tested where there are fonts.
@Suite("A day being sent somewhere")
struct EntryExportTests {
    private let march14 = JournalDay(year: 2026, month: 3, day: 14)

    // MARK: - The text form

    // The whole of "the text form is the plain markdown": not a rendering of
    // it, not a tidied version of it — the characters in the file, which is
    // what somebody pasting them into Obsidian expects to get back.
    @Test("the text form is the Entry's markdown, character for character")
    func theTextFormIsTheFile() {
        let markdown = """
            # Saturday, March 14

            Walked to *the market* and back the **long** way.

            - [x] milk
            - [ ] bread

            """

        #expect(EntryExport(march14, markdown: markdown).markdown == markdown)
    }

    @Test("nothing about the markdown is normalised on the way out")
    func nothingIsNormalised() {
        // Trailing spaces are a markdown line break, tabs are somebody's
        // indent, and a missing final newline is how the file is.
        let awkward = "# Day  \n\tindented\r\nwindows line\n\n\nno final newline"

        #expect(EntryExport(march14, markdown: awkward).markdown == awkward)
    }

    // MARK: - What the file is called

    // Named after the day, like an Attachment is, so a folder somebody
    // exported a month into sorts the way the journal does.
    @Test("both forms are named after the Journal Day")
    func namedAfterTheDay() {
        let export = EntryExport(march14, markdown: "words")

        #expect(export.fileName(as: .pdf) == "2026-03-14.pdf")
        #expect(export.fileName(as: .plainText) == "2026-03-14.md")
    }

    @Test("a single-digit month and day are padded, so names sort")
    func namesSort() {
        let july4 = EntryExport(JournalDay(year: 2026, month: 7, day: 4), markdown: "words")

        #expect(july4.fileName(as: .pdf) == "2026-07-04.pdf")
        #expect(july4.fileName(as: .plainText) == "2026-07-04.md")
    }

    // The text form keeps the extension the Journal itself uses: what comes
    // out of Aujour is a file that could go straight back into the vault.
    @Test("the text form is a markdown file, not a .txt")
    func theTextFormIsMarkdown() {
        #expect(EntryExport.Form.plainText.fileExtension == "md")
        #expect(EntryExport.Form.pdf.fileExtension == "pdf")
    }

    // MARK: - Whether there is anything to send

    @Test("a day with words in it has something to send")
    func somethingToSend() {
        #expect(EntryExport(march14, markdown: "# Day\n\nSomething happened.").hasWords)
    }

    // An Entry that is empty, or that is a template nobody filled in past its
    // blank lines, is a share sheet offering an empty page. The offer is
    // simply not made.
    @Test("a day with nothing but whitespace in it has nothing to send")
    func nothingToSend() {
        #expect(!EntryExport(march14, markdown: "").hasWords)
        #expect(!EntryExport(march14, markdown: "   \n\n\t\n").hasWords)
    }

    // MARK: - What the document is called

    // With its year, always. An exported day is read away from the app that
    // knows which week it is — in a mail attachment, in a folder of them, on
    // paper — and every February has a 14th.
    @Test("the document is titled with the day spelled out, year included")
    func titledWithTheDay() {
        let title = EntryExport(march14, markdown: "words")
            .title(in: TimeZone(identifier: "Europe/Paris")!, locale: Locale(identifier: "en_US"))

        #expect(title == "Saturday, March 14, 2026")
    }

    @Test("the title is the same words the day's own screen is titled with")
    func theSameWordsAsTheScreen() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        let french = Locale(identifier: "fr_FR")

        #expect(
            EntryExport(march14, markdown: "words").title(in: paris, locale: french)
                == march14.spelledOut(withYear: true, in: paris, locale: french)
        )
    }
}
