import AujourCore
import Foundation
import Testing
import UIKit

@testable import Aujour

// Live preview's second half. Which marks the cursor leaves hidden is Core's
// and is tested there; that they come back *in place* is only answerable once
// there is a font and a line to lay out, and it is the half the visual
// identity could have taken away.
//
// The design files draw a cursored line in monospace, which shrinks a heading
// from its styled size the moment the caret arrives. That is not what Aujour
// does: `CONTEXT.md` hides a heading's hashes precisely *because the line
// stays large*, so hiding is a fact about which glyphs are made and never
// about which font they are made in. These tests are that sentence, pinned —
// no character changes its font as the cursor moves, and no line changes
// height.
//
// What they do *not* claim is that a revealed mark takes no room. It takes
// exactly its own room, which is the point: `HiddenSyntaxDrawingTests`
// measures the line closing up when a mark goes, so a line near its wrap
// boundary gains a word back when the caret arrives on it. That is reflow by
// two characters, not the restyle of a whole line, and
// `theCaretEnteringBoldNearAWrapBoundary` is where it is written down rather
// than avoided.
//
// Nothing here is about a Drawn Element. A task's box and an embed's picture
// are stood *down* at the cursor rather than revealed, and a line that gives
// up a picture is a line that changes height on purpose — that is
// `DrawnMarkdownDrawingTests`', and the entries below leave both out so the
// claims stay about marks.

@MainActor
@Suite("Marks revealed in place")
struct MarksInPlaceTests {
    /// A day with one of everything whose marks can hide, and nothing whose
    /// drawing can stand in for it.
    private let day = """
        # Sunday

        Woke *late*, and the flat was **already warm**.

        - milk
        - bread

        > Someone said something worth keeping.

        Made `coffee`, then read [the news](https://example.com/today).
        """

    // MARK: - The size and the face

    @Test("a heading keeps its size and face when the cursor is in it")
    func aHeadingIsNotRestyledAtTheCursor() throws {
        let entry = LaidOutDay(day)
        let heading = NSRange(location: 0, length: 8)
        let read = entry.fonts(over: heading)

        entry.moveCaret(to: 3)
        #expect(entry.fonts(over: heading) == read)

        // And it really is a heading either way, rather than two readings that
        // agree because both came out as body text.
        let words = try #require(entry.font(at: 2))
        let body = try #require(entry.font(at: 12))
        #expect(words.pointSize > body.pointSize)
        #expect(words.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    // The whole of "in place": the hashes are not a smaller, plainer thing
    // that appears beside the heading — they are drawn in the heading.
    @Test("a revealed mark is drawn in the font of the line it belongs to")
    func aMarkIsDrawnInItsOwnLinesFont() throws {
        let entry = LaidOutDay(day, cursor: NSRange(location: 3, length: 0))
        #expect(entry.font(at: 0) == entry.font(at: 2))

        entry.moveCaret(to: 16)
        let star = try #require(entry.font(at: 15))
        let word = try #require(entry.font(at: 16))
        #expect(star.pointSize == word.pointSize)
    }

    // One sweep for both claims, because they are one claim: a font that never
    // changes is a line that never changes height, and the cheapest way to be
    // wrong about either is to restyle the line the caret landed on.
    @Test("no character changes its font and no line its height, wherever the cursor goes")
    func nothingIsRestyledAsTheCursorMoves() {
        let entry = LaidOutDay(day)
        let fonts = entry.fonts(over: entry.whole)
        let heights = entry.lineHeights()
        #expect(heights.count > 1)

        for caret in 0...entry.storage.length {
            entry.moveCaret(to: caret)
            #expect(
                entry.fonts(over: entry.whole) == fonts,
                "the caret at \(caret) restyled the day it landed in"
            )
            #expect(
                entry.lineHeights() == heights,
                "the caret at \(caret) changed the height of a line"
            )
        }
    }

    // MARK: - Nothing moves

    // The practical test, on the line where a restyle would show up worst: a
    // paragraph long enough to wrap, with the caret put into its plain words.
    // Nothing is revealed there, so nothing may move — not the wrap points,
    // not the number of lines, not a single fragment.
    @Test("putting the caret in a paragraph does not re-wrap it")
    func theCaretDoesNotRewrapAParagraph() {
        let entry = LaidOutDay(wrappingParagraph, width: 320)
        let lines = entry.lineFragments()
        #expect(lines.count >= 4, "the paragraph did not wrap, so it cannot prove anything")

        entry.moveCaret(to: 5)
        #expect(entry.lineFragments() == lines)
    }

    // A short heading is a heading whether or not its hashes are drawn, and
    // the day under it does not shuffle down when the caret arrives.
    @Test("a heading gaining its hashes does not move the day under it")
    func revealingAHeadingLeavesTheRestWhereItWas() {
        let entry = LaidOutDay(day, width: 320)
        let paragraph = (day as NSString).range(of: "Woke")
        let lines = entry.lineFragments()
        let below = entry.lineFragments(from: paragraph.location)

        entry.moveCaret(to: 3)
        #expect(entry.lineFragments().count == lines.count)
        #expect(entry.lineFragments(from: paragraph.location) == below)
    }

    // The case the other three avoid, written down rather than dodged.
    //
    // A mark is revealed *in place*, so it takes its own room on the line —
    // `HiddenSyntaxDrawingTests.hiddenSyntaxIsNotLaidOut` measures the line
    // closing up by exactly that much when the mark goes again. On a paragraph
    // sitting near its wrap boundary that is enough to push a word down, and
    // this test is here to say by how much: the words move, and nothing else
    // does. Every line is still the height it was, and no line was restyled.
    //
    // The alternative would be reserving the room a hidden mark would need,
    // which is the gap `CONTEXT.md` rules out — hiding is "leaving the
    // character out of the drawing", and a heading whose words started a
    // stop short of the margin would be a heading drawn around a mark that
    // is not there.
    @Test("a caret entering bold near a wrap boundary moves words and nothing else")
    func theCaretEnteringBoldNearAWrapBoundary() {
        let entry = LaidOutDay(wrappingParagraph, width: 320)
        let heights = entry.lineHeights()
        let fonts = entry.fonts(over: entry.whole)
        let widths = entry.lineUsedWidths()

        let bold = (wrappingParagraph as NSString).range(of: "already")
        entry.moveCaret(to: bold.location)

        // The four stars took their own room, and the words on that line
        // moved along to make it — which is what revealing a mark *in place*
        // costs, and the whole reason the line closed up when it was hidden.
        #expect(entry.lineUsedWidths() != widths, "revealing the marks took no room at all")

        // And that is the entire cost. Nothing was re-fonted and no line is a
        // different height, which is what the design's monospace swap would
        // have done to every line the caret touched.
        #expect(entry.fonts(over: entry.whole) == fonts, "the paragraph was restyled")
        #expect(entry.lineHeights() == heights, "a line changed height")
    }

    /// A paragraph long enough to wrap several times at a phone's width, with
    /// one emphasised phrase early enough in it that revealing the phrase's
    /// marks shifts everything after them.
    private let wrappingParagraph = """
        Woke before the alarm and the flat was **already warm**, so I made \
        coffee and sat by the window and did nothing at all for twenty slow \
        minutes while the street outside began to sound like a Sunday rather \
        than a weekday.
        """
}
