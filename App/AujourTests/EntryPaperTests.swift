import AujourCore
import Foundation
import PDFKit
import Testing
import UIKit

@testable import Aujour

// The page a day is printed on. What a PDF *says* — which day, what it is
// called, whether there is anything to send — is Core's and is tested there;
// this is the half that only exists once there are fonts and a sheet of
// paper: that the words come out, that the markdown does not, that a long day
// runs over onto a second page, and that a photograph the Entry embeds is on
// the page rather than its markdown.
//
// Read back with PDFKit rather than looked at: a page whose text can be
// extracted is a page a person can read, and it is the only assertion here
// that does not need a pair of eyes.
@MainActor
@Suite("A day drawn onto pages")
struct EntryPaperTests {
    private let march14 = JournalDay(year: 2026, month: 3, day: 14)

    /// The day as this device spells it. Read the same way the running head
    /// is rather than written out, because how a date reads is the locale's:
    /// what these tests claim is that the page says *which day it is*, and
    /// what it says it in is pinned by `EntryExportTests` against a locale of
    /// its own.
    private var theDay: String { march14.spelledOut(withYear: true) }

    private func page(of markdown: String, on paper: EntryPaper.Page = .a4) throws -> PDFPage {
        try #require(try document(of: markdown, on: paper).page(at: 0))
    }

    private func document(
        of markdown: String,
        on paper: EntryPaper.Page = .a4
    ) throws -> PDFDocument {
        let data = EntryPaper(page: paper).pdf(of: EntryExport(march14, markdown: markdown))
        return try #require(PDFDocument(data: data))
    }

    // MARK: - The words

    @Test("the day's words are on the page")
    func theWordsAreOnThePage() throws {
        let text = try #require(
            try page(of: "# Saturday\n\nWalked to the market and back.").string
        )

        #expect(text.contains("Saturday"))
        #expect(text.contains("Walked to the market and back."))
    }

    // The whole of "the PDF presents the rendered entry". There is no cursor
    // on a page, so nothing is revealed and the marks are drawn nowhere —
    // which is exactly what the editor does for a day nobody is writing in.
    @Test("the marks that made it markdown are not")
    func theMarksAreNot() throws {
        let text = try #require(
            try page(of: "## A heading\n\nA **loud** word and a *soft* one.").string
        )

        #expect(text.contains("A heading"))
        #expect(text.contains("loud"))
        #expect(text.contains("soft"))
        #expect(!text.contains("#"))
        #expect(!text.contains("*"))
    }

    // The markers that may never hide, because hiding them would leave a
    // paragraph where a list was.
    @Test("a list is still a list, and a quote still somebody else's")
    func markersThatStay() throws {
        let text = try #require(try page(of: "- milk\n- bread\n\n> Someone said this.").string)

        #expect(text.contains("- milk"))
        #expect(text.contains("> Someone said this."))
    }

    // MARK: - The sheet

    @Test("the page is the paper it was asked for")
    func thePaperItWasAskedFor() throws {
        let a4 = try page(of: "Words.", on: .a4).bounds(for: .mediaBox)
        #expect(abs(a4.width - 595.2) < 1)
        #expect(abs(a4.height - 841.8) < 1)

        let letter = try page(of: "Words.", on: .usLetter).bounds(for: .mediaBox)
        #expect(abs(letter.width - 612) < 1)
        #expect(abs(letter.height - 792) < 1)
    }

    // A day can run long, and a day cut off at the fold is a day that was not
    // sent.
    @Test("a long day runs on to as many pages as it takes, last words included")
    func aLongDayRunsOn() throws {
        let paragraph = "It rained all morning and then it stopped, which nobody expected.\n\n"
        let markdown = String(repeating: paragraph, count: 120) + "And that was that."
        let document = try document(of: markdown)

        #expect(document.pageCount > 1)
        let lastPage = try #require(document.page(at: document.pageCount - 1))
        #expect(try #require(lastPage.string).contains("And that was that."))
    }

    // A day ending exactly at a fold is the one that would leave a sheet with
    // nothing but a running head on it — which reads as a page that failed to
    // print rather than as the end of the day.
    @Test("no page is left over with nothing on it")
    func noEmptyLastPage() throws {
        // Enough lengths that one of them ends at a fold. Each is its own
        // document, so this is thirty pagination runs rather than one.
        for lines in 55...85 {
            let markdown = String(repeating: "A line about the day.\n\n", count: lines)
            let document = try document(of: markdown)
            let lastPage = try #require(document.page(at: document.pageCount - 1))
            #expect(
                try #require(lastPage.string).contains("A line about the day."),
                "\(lines) lines came out with a blank last page"
            )
        }
    }

    @Test("the day is written at the top of every page")
    func theDayIsAtTheTopOfEveryPage() throws {
        let markdown = String(repeating: "A line about the day.\n\n", count: 120)
        let document = try document(of: markdown)
        #expect(document.pageCount > 1)

        for number in 0..<document.pageCount {
            let text = try #require(document.page(at: number)?.string)
            #expect(
                text.contains(theDay),
                "page \(number + 1) does not say which day it is"
            )
            #expect(text.contains("\(number + 1) / \(document.pageCount)"))
        }
    }

    // One page says which day it is and nothing about being page one of one:
    // a page number on a single sheet is noise.
    @Test("a day that fits on one page is not numbered")
    func onePageIsNotNumbered() throws {
        let text = try #require(try page(of: "A short day.").string)

        #expect(text.contains(theDay))
        #expect(!text.contains("1 / 1"))
    }

    @Test("the document is titled with the day, so a file of them is filable")
    func titled() throws {
        let attributes = try #require(try document(of: "Words.").documentAttributes)

        #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == theDay)
    }

    // Not reachable from the share sheet — a day with nothing in it is not
    // offered — but a PDF with no pages is a file nothing will open, and that
    // is a worse answer than a blank sheet.
    @Test("a day with nothing in it still comes out as a file that opens")
    func anEmptyDayStillOpens() throws {
        let document = try document(of: "")

        #expect(document.pageCount == 1)
        #expect(try #require(document.page(at: 0)?.string).contains(theDay))
    }

    // MARK: - Ink

    // The editor's colours are the system's, and the system's resolve against
    // whatever traits the drawing happens under — so a page drawn on a phone
    // in dark mode would be white words on white paper.
    @Test("the ink is ink, whatever the phone's appearance is")
    func theInkIsInk() {
        let paper = MarkdownStyling.onPaper
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        for colour in [paper.words, paper.syntax, paper.quoted, paper.box] {
            var white: CGFloat = 1
            var alpha: CGFloat = 0
            #expect(colour.resolvedColor(with: dark).getWhite(&white, alpha: &alpha))
            #expect(white < 0.5, "a page drawn in the dark came out in \(colour)")
        }
    }
}
