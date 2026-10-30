import AujourCore
import Testing
import UIKit

@testable import Aujour

@MainActor
@Suite("The surface behind a day's words")
struct EntrySurfaceTests {
    private func editor(_ text: String = "") -> MarkdownTextView {
        let container = NSTextContainer(size: CGSize(width: 402, height: CGFloat.greatestFiniteMagnitude))
        let layout = NSLayoutManager()
        let storage = NSTextStorage(string: text, attributes: [.font: UIFont.systemFont(ofSize: 17)])
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        container.widthTracksTextView = true
        let view = MarkdownTextView(frame: CGRect(x: 0, y: 0, width: 402, height: 844), textContainer: container)
        view.font = UIFont.systemFont(ofSize: 17)
        view.baseInset = EntrySurface.textInset(lineFragmentPadding: container.lineFragmentPadding)
        view.roomForTheGlass = 100
        view.surfaceColor = AccentSurface.sheet.color(for: .driftwood)
        settle(view)
        return view
    }

    private func settle(_ view: MarkdownTextView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.layoutManager.ensureLayout(for: view.textContainer)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func surface(in view: MarkdownTextView) throws -> CALayer {
        try #require(view.layer.sublayers?.first { $0.name == "entryBodySurface" })
    }

    @Test("A short day has a tall rounded sheet around its caret")
    func aShortDay() throws {
        let view = editor("A quiet morning.")
        let paper = try surface(in: view)
        let caret = view.caretRect(for: view.beginningOfDocument)
        let firstLine = view.layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            .offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
        #expect(paper.frame.height == 480)
        #expect(paper.frame.minX == 16)
        #expect(paper.frame.maxX == view.bounds.width - 16)
        #expect(paper.cornerRadius == 32)
        #expect(caret.midX - paper.frame.minX == 22)
        #expect(firstLine.minY >= paper.frame.minY + 22)
        #expect(view.contentInset == .zero)
    }

    @Test("A long day's sheet contains its last line and contracts after deleting the text")
    func aLongDay() throws {
        let view = editor(String(repeating: "A line to remember.\n", count: 100))
        let paper = try surface(in: view)
        let caret = view.caretRect(for: view.endOfDocument)
        #expect(paper.frame.height > view.bounds.height)
        #expect(paper.frame.maxY >= caret.maxY + 20)
        let frame = paper.frame
        view.contentOffset.y = 200
        settle(view)
        #expect(paper.frame == frame)
        view.text = "A shorter day."
        view.contentOffset = .zero
        settle(view)
        #expect(paper.frame.height == 480)
    }

    @Test("An empty sheet fits when the keyboard or a small window leaves less room")
    func aSmallWindow() throws {
        let view = editor()
        view.frame.size.height = 250
        settle(view)
        let paper = try surface(in: view)
        #expect(paper.frame.height < 480)
        #expect(paper.frame.maxY <= view.bounds.height - 16)
        #expect(paper.frame.contains(view.caretRect(for: view.beginningOfDocument)))
        #expect(view.contentInset == .zero)
    }

    @Test("The sheet follows the resolved appearance without replacing its text")
    func appearanceChanges() throws {
        let view = editor("Words stay here.")
        let paper = try surface(in: view)
        view.traitOverrides.userInterfaceStyle = .light
        view.updateTraitsIfNeeded()
        settle(view)
        let light = paper.backgroundColor
        view.traitOverrides.userInterfaceStyle = .dark
        view.updateTraitsIfNeeded()
        settle(view)
        #expect(paper.backgroundColor != light)
        #expect(paper.backgroundColor == view.surfaceColor?.resolvedColor(with: view.traitCollection).cgColor)
        #expect(view.text == "Words stay here.")
    }

}
