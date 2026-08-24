import AujourCore
import Foundation
import PDFKit
import Testing
import UIKit

@testable import Aujour

// What actually leaves the app when somebody sends a day: a file, named after
// the day, holding either the Entry's own characters or a page drawn from
// them. The share sheet itself is the system's screen and not this suite's
// subject — everything up to handing it a URL is Aujour's, and all of it is
// here.
@MainActor
@Suite("A day handed to the share sheet")
struct SharedEntryTests {
    private let march14 = JournalDay(year: 2026, month: 3, day: 14)

    private func shared(
        _ markdown: String,
        as form: EntryExport.Form,
        drawnWith pictures: EmbeddedPictures? = nil
    ) async throws -> SharedEntry.File {
        let sharing = SharedEntry()
        await sharing.share(EntryExport(march14, markdown: markdown), as: form, drawnWith: pictures)
        #expect(sharing.problem == nil)
        return try #require(sharing.file)
    }

    // MARK: - The text form

    // The acceptance criterion, and ADR 0001 on its way out of the app: what
    // is sent is the file, not a rendering of it and not a tidied version of
    // it.
    @Test("the text form is the Entry's own characters, byte for byte")
    func theTextFormIsTheEntry() async throws {
        let markdown = "# Saturday  \n\n- [x] milk\n- [ ] bread\n\n> Someone said this.\n"

        let file = try await shared(markdown, as: .plainText)

        #expect(try Data(contentsOf: file.url) == Data(markdown.utf8))
    }

    @Test("the text form is a markdown file named after the day")
    func theTextFormIsNamedAfterTheDay() async throws {
        let file = try await shared("Words.", as: .plainText)

        #expect(file.url.lastPathComponent == "2026-03-14.md")
    }

    // MARK: - The PDF form

    @Test("the PDF form is a PDF named after the day")
    func thePDFFormIsAPDF() async throws {
        let file = try await shared("# Saturday\n\nWalked to the market.", as: .pdf)

        #expect(file.url.lastPathComponent == "2026-03-14.pdf")
        let document = try #require(PDFDocument(url: file.url))
        #expect(document.pageCount == 1)
        #expect(try #require(document.page(at: 0)?.string).contains("Walked to the market."))
    }

    // MARK: - Photographs

    // A page carrying `![the market](…)` where the photograph should be is a
    // page nobody meant to send — so the embed is waited for rather than
    // drawn as whatever the screen happened to have found by then.
    @Test("a photograph the day embeds is on the page, not its markdown")
    func aPhotographIsOnThePage() async throws {
        let embed = "attachments/2026/03/2026-03-14.png"
        let markdown = "# Saturday\n\n![the market](\(embed))\n"
        let store = InMemoryJournalStore([PathTemplate.default.render(march14): markdown])
        try await store.write(try #require(redSquare()), at: embed)

        let editor = EntryEditor(store: store, day: march14)
        await editor.open()
        try #require(editor.state.isEditing)

        // Nothing has been drawn yet, so nothing has been looked for — which
        // is the moment somebody who opened a day and reached straight for
        // the share button is in.
        let pictures = EmbeddedPictures()
        pictures.look(in: editor)

        let file = try await shared(editor.content, as: .pdf, drawnWith: pictures)

        // Waited for on the way to the page, rather than found later and
        // drawn into a PDF nobody is looking at any more.
        #expect(pictures.picture(for: embed) != nil, "the photograph was never found")

        let page = try #require(PDFDocument(url: file.url)?.page(at: 0))
        #expect(!(try #require(page.string).contains(embed)), "the markdown was drawn, not the photo")
        #expect(isRedSomewhere(page), "the photograph is not on the page")
    }

    // MARK: - The scratch folder

    // One file at a time in a folder of Aujour's own. What is shared is a copy
    // handed to something else; the journal is the folder, and nothing made
    // for a share sheet belongs in it or outlives the next one.
    @Test("sharing a day again leaves only the newest file behind")
    func onlyTheNewestFile() async throws {
        let text = try await shared("Words.", as: .plainText)
        let pdf = try await shared("Words.", as: .pdf)

        #expect(FileManager.default.fileExists(atPath: pdf.url.path))
        #expect(!FileManager.default.fileExists(atPath: text.url.path))
        #expect(
            try FileManager.default.contentsOfDirectory(
                atPath: pdf.url.deletingLastPathComponent().path
            ) == ["2026-03-14.pdf"]
        )
    }

    // MARK: - A red square, and finding it again

    /// A photograph that is unmistakable on a page: pure red, and big enough
    /// that a page drawn at any margin has some of it.
    private func redSquare() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }.pngData()
    }

    /// Whether anything on this page is that red — the one assertion about a
    /// drawing that does not need a pair of eyes.
    ///
    /// Drawn into a bitmap this test lays out itself rather than into one
    /// `UIGraphicsImageRenderer` chose, because the question is about
    /// particular bytes: a renderer's own image is BGRA on this platform, and
    /// read as RGBA a red square is a blue one.
    private func isRedSomewhere(_ page: PDFPage) -> Bool {
        let side = 300
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard
            let context = CGContext(
                data: &pixels,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return false }

        let bounds = page.bounds(for: .mediaBox)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.scaleBy(x: CGFloat(side) / bounds.width, y: CGFloat(side) / bounds.height)
        page.draw(with: .mediaBox, to: context)

        return stride(from: 0, to: pixels.count - 4, by: 4).contains {
            pixels[$0] > 200 && pixels[$0 + 1] < 80 && pixels[$0 + 2] < 80
        }
    }
}
