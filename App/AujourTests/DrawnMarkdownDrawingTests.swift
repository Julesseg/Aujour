import AujourCore
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Aujour

// The editor's half of checkboxes and inline embeds. Which stretches are stood
// in front of, and what each one points at, is decided in Core and tested
// there against the text it came from; what is left is the part that only
// exists once there is a font, a layout and a photograph — that a box really
// takes a box's room on the line, that a picture makes its line as tall as it
// is, that an embed nobody can resolve is still the markdown it always was,
// and that tapping a box rewrites one character of the file.
//
// Headless, and no simulator screenshot in sight: a text storage with a layout
// manager attached is enough to ask how big anything came out.

@MainActor
@Suite("Boxes and pictures in place of an entry's own characters")
struct DrawnMarkdownDrawingTests {
    private let styling = MarkdownStyling()

    private func storage(holding source: String, cursor: NSRange?) -> MarkdownTextStorage {
        let storage = MarkdownTextStorage(styling: styling)
        storage.setSource(source)
        storage.cursor = cursor
        return storage
    }

    private func storage(holding source: String, caret: Int) -> MarkdownTextStorage {
        storage(holding: source, cursor: NSRange(location: caret, length: 0))
    }

    /// What the storage marked as drawn over, as the characters each drawing
    /// stands in front of.
    private func drawings(in storage: MarkdownTextStorage) -> [(text: String, kind: String)] {
        var found: [(String, String)] = []
        storage.enumerateAttribute(
            .drawnMarkdown,
            in: NSRange(location: 0, length: storage.length)
        ) { value, _, _ in
            guard let drawn = value as? DrawnMarkdown else { return }
            let text = (storage.string as NSString).substring(with: drawn.text)
            switch drawn.kind {
            case .taskBox(let isDone, _):
                found.append((text, isDone ? "ticked box" : "empty box"))
            case .picture:
                found.append((text, "picture"))
            case .widget(let placeholder, _):
                // Which is `PlaceholderWidgetTests`' subject, and here only so
                // that a day holding one is described rather than dropped.
                found.append((text, "\(placeholder.rawValue) widget"))
            }
        }
        return found
    }

    // MARK: - Boxes

    @Test("a task's marker is drawn as a box while the cursor is elsewhere")
    func taskBoxes() {
        let entry = storage(holding: "- [ ] milk\n- [x] bread", caret: 22)
        let drawn = drawings(in: entry)
        #expect(drawn.map(\.text) == ["- [ ] "])
        #expect(drawn.map(\.kind) == ["empty box"])

        entry.cursor = NSRange(location: 0, length: 0)
        #expect(drawings(in: entry).map(\.kind) == ["ticked box"])
    }

    @Test("the box gives way to its own markdown at the cursor")
    func aTaskAtTheCursor() {
        let entry = storage(holding: "- [x] milk", caret: 3)
        #expect(drawings(in: entry).isEmpty)

        entry.cursor = nil
        #expect(drawings(in: entry).map(\.text) == ["- [x] "])
    }

    // What the attribute is for, and the only test that can see it: the
    // marker's own characters take up no room, and the box takes a box's
    // worth in their place.
    @Test("a box takes a box's room, and the marker under it takes none")
    func aBoxIsLaidOut() {
        let marker = NSRange(location: 0, length: 6)

        let drawn = laidOut("- [ ] milk", cursor: nil)
        let written = laidOut("- [ ] milk", cursor: NSRange(location: 2, length: 0))

        #expect(drawn.width(of: marker) > 0, "the box took no room at all")
        #expect(written.width(of: marker) > 0)
        // Six characters of markdown are wider than one box, which is the
        // whole visual point of drawing one.
        #expect(
            drawn.width(of: marker) < written.width(of: marker),
            "the box was no narrower than the `- [ ] ` it stands in for"
        )
        // And the words after it start after the box rather than after a gap
        // where six characters used to be.
        #expect(drawn.lineWidth(atCharacter: 0) < written.lineWidth(atCharacter: 0))
    }

    @Test("a line with no box on it is laid out exactly as before")
    func linesWithoutABox() {
        #expect(drawings(in: storage(holding: "- milk\n1. bread\n> quoted", cursor: nil)).isEmpty)
    }

    // MARK: - Ticking one

    /// The edit a tap at this character would make, or `nil` where it would
    /// land on something that is not a box.
    private func ticking(_ entry: MarkdownTextStorage, at character: Int) -> MarkdownEdit? {
        guard case .box(let edit) = entry.tapping(at: character) else { return nil }
        return edit
    }

    @Test("tapping a box asks for the one character that ticks it")
    func tickingABox() {
        let entry = storage(holding: "- [ ] milk\n- [x] bread", cursor: nil)
        #expect(
            ticking(entry, at: 0)
                == MarkdownEdit(range: NSRange(location: 3, length: 1), replacement: "x")
        )
        #expect(
            ticking(entry, at: 11)
                == MarkdownEdit(range: NSRange(location: 14, length: 1), replacement: " ")
        )
    }

    // The tap is on the box, and the box is drawn over one character. Anywhere
    // else on the line is words, and a tap on words moves the caret.
    @Test("a tap that is not on a box is not a tick")
    func tappingElsewhere() {
        let entry = storage(holding: "- [ ] milk", cursor: nil)
        #expect(ticking(entry, at: 3) == nil)
        #expect(ticking(entry, at: 7) == nil)
        #expect(ticking(entry, at: 400) == nil)
    }

    // A line showing its own markdown has no box on it to tap: the cursor is
    // in it, and the brackets are there to be edited by hand.
    @Test("a task at the cursor has no box to tap")
    func tappingATaskBeingEdited() {
        #expect(ticking(storage(holding: "- [ ] milk", caret: 2), at: 0) == nil)
    }

    @Test("ticking a box changes one character of the entry and nothing else")
    func tickingRewritesTheText() {
        let entry = storage(holding: "# Sunday\n\n- [ ] milk\n- [x] bread", cursor: nil)
        let edit = try! #require(ticking(entry, at: 10))
        entry.replaceCharacters(in: edit.range, with: edit.replacement)

        #expect(entry.string == "# Sunday\n\n- [x] milk\n- [x] bread")
    }

    // MARK: - A finger on a box

    @Test("a tap on the box ticks it, and leaves the caret where it was")
    func tappingTheBox() {
        let entry = editor(holding: "- [ ] Milk\n- [ ] Bread\n")
        #expect(entry.coordinator.tapped(in: entry.textView, at: entry.firstBox))

        #expect(entry.textView.text == "- [x] Milk\n- [ ] Bread\n")
        // And the Entry hears about it, which is what saves it.
        #expect(entry.written == "- [x] Milk\n- [ ] Bread\n")
        #expect(entry.textView.selectedRange == NSRange(location: 0, length: 0))

        // And again, the other way.
        #expect(entry.coordinator.tapped(in: entry.textView, at: entry.firstBox))
        #expect(entry.written == "- [ ] Milk\n- [ ] Bread\n")
    }

    // A tick is an edit, and the day it is in is full of other edits: shaking
    // to undo after ticking the wrong line should take back the tick rather
    // than the sentence typed before it.
    @Test("a tick can be undone, like any other edit")
    func undoingATick() throws {
        let entry = editor(holding: "- [ ] Milk\n")
        entry.coordinator.tapped(in: entry.textView, at: entry.firstBox)
        #expect(entry.textView.text == "- [x] Milk\n")

        let undo = try #require(entry.textView.undoManager)
        #expect(undo.canUndo)
        undo.undo()

        #expect(entry.textView.text == "- [ ] Milk\n")
        #expect(entry.written == "- [ ] Milk\n")
    }

    // A tap on words is the text view's, and moves the caret like any other.
    @Test("a tap that is not on a box does nothing at all")
    func tappingBesideTheBox() {
        let entry = editor(holding: "- [ ] Milk\n")
        var beside = entry.firstBox
        beside.x += 120

        #expect(!entry.coordinator.tapped(in: entry.textView, at: beside))
        #expect(entry.written == nil)

        // And well below the last line, which is where a tap on the empty
        // space under a short entry lands.
        #expect(!entry.coordinator.tapped(in: entry.textView, at: CGPoint(x: 20, y: 400)))
        #expect(entry.written == nil)
    }

    // MARK: - Pictures

    @Test("an embed nobody can resolve is left as the markdown it is")
    func unresolvableEmbeds() {
        // No folder to look in at all, which is the same answer as a folder
        // with nothing in it: the words stay, visible and harmless.
        for embed in ["![the market](market.jpg)", "![[market.jpg]]"] {
            let entry = storage(holding: "Walked to \(embed) and back.", cursor: nil)
            #expect(drawings(in: entry).isEmpty, "\(embed) was drawn over with nothing")
            #expect(entry.string.contains(embed))
        }
    }

    @Test("an embed whose picture is there is drawn as the picture, in either spelling")
    func embedsBecomePictures() async throws {
        let market = try await aMarketToDrawFrom()

        for embed in ["![the market](market.jpg)", "![[market.jpg]]"] {
            let entry = storage(holding: "Walked to \(embed)", cursor: nil)
            entry.pictures = market.pictures
            entry.aPictureArrived()

            let drawn = drawings(in: entry)
            #expect(drawn.map(\.text) == [embed], "\(embed) was not drawn as its picture")
            #expect(drawn.map(\.kind) == ["picture"])
        }
    }

    @Test("the embed's own markdown comes back at the cursor")
    func anEmbedAtTheCursor() async throws {
        let market = try await aMarketToDrawFrom()
        let entry = storage(holding: "![[market.jpg]]", cursor: nil)
        entry.pictures = market.pictures
        entry.aPictureArrived()
        #expect(drawings(in: entry).count == 1)

        entry.cursor = NSRange(location: 4, length: 0)
        #expect(drawings(in: entry).isEmpty)
    }

    // A picture is not a character-sized thing, and the line it is on has to
    // grow to hold it — otherwise it would be painted over the words below.
    @Test("a picture makes room for itself on the line it is on")
    func aPictureIsLaidOut() async throws {
        let market = try await aMarketToDrawFrom()
        let entry = "Walked to\n![[market.jpg]]\nand back."

        let withPicture = laidOut(entry, cursor: nil, pictures: market.pictures)
        let withoutPicture = laidOut(entry, cursor: nil)

        let embedLine = 10
        #expect(withPicture.lineHeight(atCharacter: embedLine) > 100)
        #expect(
            withPicture.lineHeight(atCharacter: embedLine)
                > withoutPicture.lineHeight(atCharacter: embedLine) * 3
        )
        // And the line below is below the picture rather than under it.
        #expect(withPicture.lineTop(atCharacter: 26) >= withPicture.lineHeight(atCharacter: 10))
    }

    // MARK: - Turning what the folder holds into a picture

    // Which file a target names is `EntryAttachmentTests` in Core, over a
    // folder and without a screen. What is left for here is the half that
    // needs one: bytes that are a photograph become a picture, and bytes that
    // are not become nothing at all — which is the same answer as a file that
    // was never there, and draws the same markdown.
    @Test("a file that is not a picture is not a picture")
    func filesThatAreNotPictures() async throws {
        let store = InMemoryJournalStore()
        try await store.writeText("not a photograph", at: "2026/03/market.jpg")
        let open = await day(over: store)

        #expect(await found(in: open.pictures, "market.jpg") == nil)
        #expect(await found(in: open.pictures, "nothing.jpg") == nil)
    }

    // The folder is shared, so a photo an Entry names can arrive after the
    // Entry did — and a "not there" that stood for the life of the day would
    // leave it undrawable until the day was left and come back to.
    @Test("a target that was not there is looked for again when the app comes back")
    func lookingAgain() async throws {
        let store = InMemoryJournalStore()
        let open = await day(over: store)
        #expect(await found(in: open.pictures, "market.jpg") == nil)

        try await store.write(marketPicture(), at: "2026/03/market.jpg")
        #expect(open.pictures.picture(for: "market.jpg") == nil, "a failure is remembered")

        open.pictures.lookAgainForWhatWasMissing()
        #expect(await found(in: open.pictures, "market.jpg") != nil)
    }

    // MARK: - A folder with one photograph in it

    /// A picture, as bytes a folder could hold.
    private func marketPicture() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        return image.pngData()!
    }

    /// A day open over that folder, and the pictures its embeds point at.
    ///
    /// Both, because the pictures know their Entry weakly — being only a
    /// drawer of what it holds — so a test has to keep the day it is about.
    /// Over the real editor rather than a stand-in, because which file a
    /// target names is the editor's to answer and standing in for it here
    /// would be testing the stand-in.
    private func day(over store: InMemoryJournalStore) async -> (
        entry: EntryEditor, pictures: EmbeddedPictures
    ) {
        let entry = EntryEditor(store: store, day: JournalDay(year: 2026, month: 3, day: 14))
        await entry.open()

        let pictures = EmbeddedPictures()
        pictures.look(in: entry)
        return (entry, pictures)
    }

    private func aMarketToDrawFrom() async throws -> (entry: EntryEditor, pictures: EmbeddedPictures)
    {
        let store = InMemoryJournalStore()
        try await store.write(marketPicture(), at: "2026/03/market.jpg")

        let open = await day(over: store)
        _ = await found(in: open.pictures, "market.jpg")
        return open
    }

    /// The picture, once looking for it has finished — which it does off the
    /// main actor, so this is the wait the editor never has to make.
    private func found(in pictures: EmbeddedPictures, _ target: String) async -> UIImage? {
        for _ in 0..<300 {
            if let picture = pictures.picture(for: target) { return picture }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    // MARK: - A real text view to tap in

    private func editor(holding source: String) -> OpenEditor {
        OpenEditor(holding: source, styling: styling)
    }

    // MARK: - Laying a day out for real

    /// An Entry laid out by the editor's own layout manager and glyph
    /// delegate — the only way to ask how big anything actually came out.
    @MainActor
    private struct LaidOut {
        let layoutManager: NSLayoutManager
        let container: NSTextContainer
        /// Both held for the same reason, and neither of them decoration: a
        /// layout manager keeps neither its delegate nor its text storage
        /// alive, and a storage that went away under it would take the
        /// attributes these measurements are about with it.
        let storage: MarkdownTextStorage
        let glyphs: MarkdownGlyphs

        func width(of characters: NSRange) -> CGFloat {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characters,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { return 0 }
            return layoutManager.boundingRect(forGlyphRange: glyphRange, in: container).width
        }

        func lineWidth(atCharacter character: Int) -> CGFloat {
            lineFragment(atCharacter: character).width
        }

        func lineHeight(atCharacter character: Int) -> CGFloat {
            lineFragment(atCharacter: character).height
        }

        func lineTop(atCharacter character: Int) -> CGFloat {
            lineFragment(atCharacter: character).minY
        }

        private func lineFragment(atCharacter character: Int) -> CGRect {
            let glyph = layoutManager.glyphIndexForCharacter(at: character)
            return layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        }
    }

    private func laidOut(
        _ source: String,
        cursor: NSRange?,
        pictures: EmbeddedPictures? = nil
    ) -> LaidOut {
        let storage = MarkdownTextStorage(styling: styling)
        let layoutManager = MarkdownLayoutManager()
        let glyphs = MarkdownGlyphs()
        let container = NSTextContainer(
            size: CGSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        )

        layoutManager.delegate = glyphs
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        storage.pictures = pictures
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
