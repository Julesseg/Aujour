import AujourCore
import UIKit

/// A day drawn onto pages: the Entry as a PDF somebody can read, mail or
/// print.
///
/// The same drawing the editor does, onto paper instead of a screen. That is
/// not a resemblance — it is literally the same three objects
/// (``MarkdownTextStorage``, ``MarkdownGlyphs``, ``MarkdownLayoutManager``)
/// over page-sized containers instead of one text view's. So a heading is the
/// size it is in the app, a task's box is the box the app draws, an embed is
/// the photograph, and the syntax that is not drawn on screen is not drawn
/// here either — because there is no cursor on a page, and a day nobody is
/// writing in shows no marks anywhere (``AujourCore/HiddenSyntax``).
///
/// That is the whole reason there is no second markdown renderer in this app.
/// A PDF built from its own idea of what `##` means would drift from the
/// editor the first time either changed, and the day somebody printed would
/// stop being the day they wrote.
///
/// ## What is added to the page
///
/// The day, small and quiet at the top, and a page number where there is more
/// than one page. Nothing else — no logo, no footer, no "exported from".
/// A journal entry that arrives as an advertisement is one nobody sends
/// twice.
@MainActor
struct EntryPaper {
    /// The sheet being drawn on, and the margin the words keep off its edges.
    struct Page: Equatable {
        let size: CGSize
        let margin: CGFloat

        /// The height of the line the day is written on, plus the air under
        /// it. On `Page` rather than beside the drawing that uses it, because
        /// it is what the words have to keep clear of and the room they get
        /// is arithmetic here.
        static let runningHead: CGFloat = 26

        /// A4, which is what most of the world prints on.
        static let a4 = Page(size: CGSize(width: 595.2, height: 841.8), margin: 56)

        /// US Letter — shorter and wider, and what a printer in the US is
        /// loaded with.
        static let usLetter = Page(size: CGSize(width: 612, height: 792), margin: 56)

        /// The paper this device's owner is likely to put in a printer.
        ///
        /// Read from the locale's measurement system rather than from a
        /// setting, because a page size is not a decision anybody wants to be
        /// asked to make about their journal — and because getting it wrong
        /// costs only a margin, which is the right size of consequence for a
        /// guess.
        static var forThisLocale: Page {
            Locale.current.measurementSystem == .us ? .usLetter : .a4
        }

        /// The room the Entry itself is drawn in: the sheet, less the
        /// margins, less the line the day is written on.
        var textArea: CGSize {
            CGSize(
                width: size.width - margin * 2,
                height: size.height - margin * 2 - Page.runningHead
            )
        }

        /// Where that room starts, in the page's own coordinates.
        var textOrigin: CGPoint {
            CGPoint(x: margin, y: margin + Page.runningHead)
        }
    }

    var page: Page = .forThisLocale

    /// How the markdown is drawn on paper — the editor's own styling, in ink.
    var styling: MarkdownStyling = .onPaper

    /// Where the pictures an embed points at come from. `nil` is a page where
    /// every embed is the markdown it is, which is also what an embed naming
    /// nothing comes out as.
    var pictures: EmbeddedPictures?

    /// A runaway guard and nothing else. A journal day is a page or three; a
    /// day that wanted two hundred is a day something has gone wrong about,
    /// and stopping is better than a renderer that never returns.
    private static let mostPages = 200

    /// Draws the day, and hands back the PDF.
    ///
    /// Always at least one page, even for a day with nothing on it — a PDF
    /// with no pages in it is a file nothing will open, and a blank sheet is
    /// at least an honest answer. Whether a day empty enough to produce one
    /// is offered for sharing at all is ``AujourCore/EntryExport/hasWords``'s.
    func pdf(of export: EntryExport) -> Data {
        let storage = MarkdownTextStorage(styling: styling)
        storage.pictures = pictures

        let layout = MarkdownLayoutManager()
        // Held for as long as the drawing takes: a layout manager does not
        // keep its delegate alive, and without this one there is no live
        // preview — every hash and every star would be on the page.
        let glyphs = MarkdownGlyphs()
        storage.addLayoutManager(layout)
        layout.delegate = glyphs
        // Every page has to be laid out before the first one can be drawn, so
        // there is nothing to be gained by putting any of it off.
        layout.allowsNonContiguousLayout = false
        storage.setSource(export.markdown)

        let pages = paginate(layout)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: export.title(),
            kCGPDFContextCreator as String: "Aujour",
        ]

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: page.size),
            format: format
        )
        // The storage and the delegate are held to the end on purpose: a
        // layout manager keeps neither alive, and both are last *mentioned*
        // well before the drawing that needs them. Without this the page
        // would come out blank, or with every mark on it, depending on which
        // one went first.
        return withExtendedLifetime((storage, glyphs)) {
            renderer.pdfData { context in
                for (index, container) in pages.enumerated() {
                    context.beginPage()
                    drawRunningHead(export, page: index + 1, of: pages.count)

                    let onThisPage = layout.glyphRange(for: container)
                    layout.drawBackground(forGlyphRange: onThisPage, at: page.textOrigin)
                    layout.drawGlyphs(forGlyphRange: onThisPage, at: page.textOrigin)
                }
                // A day with nothing on it still leaves a file somebody can
                // open.
                if pages.isEmpty {
                    context.beginPage()
                    drawRunningHead(export, page: 1, of: 1)
                }
            }
        }
    }

    /// The first page, drawn — the page somebody is about to send, so that
    /// they can see what it looks like before it leaves.
    ///
    /// The document itself and not a second drawing of the day: what is
    /// previewed is the file, down to the running head, the margins and where
    /// the lines break. Getting it costs drawing the whole PDF, which is what
    /// it costs to be able to say that — and it is the same drawing the share
    /// itself does a moment later.
    ///
    /// `nil` for a day that would not draw at all, which is a preview the
    /// screen simply does not show.
    func firstPage(of export: EntryExport) -> UIImage? {
        guard let bytes = CGDataProvider(data: pdf(of: export) as CFData),
            let document = CGPDFDocument(bytes),
            let first = document.page(at: 1)
        else { return nil }

        let sheet = first.getBoxRect(.mediaBox)
        let format = UIGraphicsImageRendererFormat()
        // A point per point rather than the screen's scale: the page is nearly
        // six hundred points wide and lands on screen at about two hundred, so
        // every extra pixel is one thrown away on the way down.
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: sheet.size, format: format).image { drawing in
            // Paper, and the app's own near-white is not it: a PDF is drawn on
            // whatever the reader opens it over, which is white.
            UIColor.white.setFill()
            drawing.fill(CGRect(origin: .zero, size: sheet.size))
            // PDF pages are drawn from the bottom left and images from the top
            // left, which is the whole of this flip.
            drawing.cgContext.translateBy(x: 0, y: sheet.height)
            drawing.cgContext.scaleBy(x: 1, y: -1)
            drawing.cgContext.drawPDFPage(first)
        }
    }

    /// Hands the layout a page-sized container at a time until the day has
    /// somewhere to be.
    ///
    /// Containers rather than one long column cut into slices, because
    /// TextKit is what knows where a line may be broken — a heading is not
    /// severed across the fold, and a photograph that will not fit on what is
    /// left of a page moves to the next one whole.
    private func paginate(_ layout: NSLayoutManager) -> [NSTextContainer] {
        var pages: [NSTextContainer] = []
        let glyphs = layout.numberOfGlyphs
        guard glyphs > 0 else { return [] }

        while pages.count < Self.mostPages {
            let container = NSTextContainer(size: page.textArea)
            // The editor's inset is the text view's; here the margin is the
            // page's, and a second one inside it would be a margin nobody
            // asked for.
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            pages.append(container)

            let laidOut = layout.glyphRange(for: container)
            if laidOut.upperBound >= glyphs { break }
            // Nothing fit on a whole empty page, so nothing will fit on the
            // next one either. Stopping loses the tail of a day; spinning
            // loses the app.
            if laidOut.length == 0 { break }
        }

        // An Entry nearly always ends in a blank line, and a blank line that
        // lands past the fold is a whole sheet with nothing on it but the
        // running head — which reads as a page that failed to print rather
        // than as the end of the day.
        //
        // Trimmed at the end rather than refused as it happens, because a
        // page of blank lines *inside* a day is followed by the rest of it,
        // and stopping at the first one would cut the day short.
        while let last = pages.last, isBlank(last, in: layout) {
            pages.removeLast()
        }
        return pages
    }

    /// Whether a page has anything on it but whitespace.
    ///
    /// Asked of the characters rather than of the ink, and so the same
    /// question ``AujourCore/EntryExport/hasWords`` asks of a whole day: a
    /// sheet holding one newline holds nothing somebody would want printed.
    private func isBlank(_ container: NSTextContainer, in layout: NSLayoutManager) -> Bool {
        guard let text = layout.textStorage?.string as NSString? else { return true }
        let characters = layout.characterRange(
            forGlyphRange: layout.glyphRange(for: container),
            actualGlyphRange: nil
        )
        guard characters.length > 0 else { return true }
        return text.substring(with: characters).allSatisfy(\.isWhitespace)
    }

    /// The day, at the top of every page, above a hairline — and which page
    /// this is, where there is more than one.
    ///
    /// Chrome rather than content, and drawn like it: small, grey, and clear
    /// of the words. A day whose first line is already `# Saturday, March 14`
    /// says it twice, which is what every printed document does and what
    /// makes the second and third sheet of one filable.
    private func drawRunningHead(_ export: EntryExport, page number: Int, of pages: Int) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor.darkGray,
        ]
        let top = page.margin
        let day = export.title() as NSString
        day.draw(at: CGPoint(x: page.margin, y: top), withAttributes: attributes)

        if pages > 1 {
            let counted = "\(number) / \(pages)" as NSString
            let width = counted.size(withAttributes: attributes).width
            counted.draw(
                at: CGPoint(x: page.size.width - page.margin - width, y: top),
                withAttributes: attributes
            )
        }

        let rule = UIBezierPath()
        let baseline = (top + 15).rounded()
        rule.move(to: CGPoint(x: page.margin, y: baseline))
        rule.addLine(to: CGPoint(x: page.size.width - page.margin, y: baseline))
        rule.lineWidth = 0.5
        UIColor.lightGray.setStroke()
        rule.stroke()
    }
}

extension MarkdownStyling {
    /// The editor's styling, in ink.
    ///
    /// Every colour spelled out, because the dynamic ones the editor uses
    /// resolve against whatever traits the drawing happens under — and a page
    /// drawn while the phone is in dark mode would be white words on white
    /// paper. `.label` is the right answer on a screen and a bug on a sheet.
    ///
    /// A fixed size, for the same reason: the editor follows Dynamic Type
    /// because it is being read at arm's length by the person who set it, and
    /// a PDF is read by somebody else on a device that never heard of them.
    /// So a page is a page, whatever the phone that made it.
    static var onPaper: MarkdownStyling {
        MarkdownStyling(
            body: .systemFont(ofSize: 11),
            words: .black,
            // Darker than the editor's tertiary grey. What survives on a page
            // is a list's `- ` and a quote's `> ` — the markers that may never
            // hide, because they are the only thing saying what the line is —
            // and a marker nobody can see is a list that reads as prose.
            syntax: UIColor(white: 0.45, alpha: 1),
            quoted: UIColor(white: 0.3, alpha: 1),
            // Dark enough to read on paper, blue enough to still be a link.
            link: UIColor(red: 0.13, green: 0.3, blue: 0.55, alpha: 1),
            box: UIColor(white: 0.2, alpha: 1),
            lineSpacing: 3
        )
    }
}
