import Foundation
import Testing
import UIKit

@testable import Aujour

/// How much room a day keeps below its last line for the row above the
/// keyboard.
///
/// The row is a pane over the page and not a floor under it, so a day scrolled
/// to its end would come to rest with its last line beneath the glass and
/// nowhere further to go — the same complaint the pill's end of the page had,
/// upside down. What answers it is the room the page keeps below the words,
/// and how much that is depends on where the row actually is.
///
/// Held here rather than in a screenshot because the thing worth proving is a
/// rule about two rectangles, and where those rectangles come from — a first
/// responder, a keyboard mid-animation, a row that docks itself above a
/// hardware one — is exactly what a simulator makes slow and a device makes
/// unrepeatable. ``MarkdownTextView`` takes the two off the screen and this
/// says what to do with them.
@MainActor
@Suite("The room a day keeps below its last line")
struct RoomBelowTheWordsTests {
    /// The usual case: the row is docked over the bottom of the page, and the
    /// room is exactly how far up into it the row reaches.
    @Test("A row over the page asks for as much room as it covers")
    func aRowOverThePage() {
        let page = CGRect(x: 0, y: 0, width: 402, height: 840)
        let row = CGRect(x: 0, y: 780, width: 402, height: 94)
        #expect(MarkdownTextView.room(below: page, coveredBy: row) == 60)
    }

    /// The layout the simulator and a docked hardware keyboard both give: the
    /// page has already been shortened to stop where the row starts, so the
    /// row is over nothing and asks for nothing.
    @Test("A row the page already stops above asks for nothing")
    func aRowBelowThePage() {
        let page = CGRect(x: 0, y: 0, width: 402, height: 780)
        let row = CGRect(x: 0, y: 780, width: 402, height: 94)
        #expect(MarkdownTextView.room(below: page, coveredBy: row) == 0)
    }

    /// And a row further down still is further below nothing. Room is never
    /// negative: a page cannot borrow space back off a pane that is not on it.
    @Test("A row clear of the page never asks for less than nothing")
    func aRowClearOfThePage() {
        let page = CGRect(x: 0, y: 0, width: 402, height: 600)
        let row = CGRect(x: 0, y: 780, width: 402, height: 94)
        #expect(MarkdownTextView.room(below: page, coveredBy: row) == 0)
    }

    /// A page scrolled up the screen — which is what the page is on a window
    /// with a bar over it — is measured where it is and not where it started.
    @Test("The room is measured from where the page actually sits")
    func aPageThatDoesNotStartAtTheTop() {
        let page = CGRect(x: 0, y: 120, width: 402, height: 720)
        let row = CGRect(x: 0, y: 780, width: 402, height: 94)
        #expect(MarkdownTextView.room(below: page, coveredBy: row) == 60)
    }
}
