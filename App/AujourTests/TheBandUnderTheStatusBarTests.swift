import Foundation
import Testing
import UIKit

@testable import Aujour

/// How deep the band is that softens a day's words under the status bar.
///
/// The page runs up under the status bar to get behind the pill's glass, and
/// the words going up past the clock soften into the system's edge effect
/// rather than run through it. The effect covers as much of the page as the
/// status bar does, which is a rule about two rectangles — held here, where a
/// notice arriving over the page is a number rather than a folder that has to
/// be made to disagree with itself.
@MainActor
@Suite("The band under the status bar")
struct TheBandUnderTheStatusBarTests {
    /// The phone's page, which starts at the top of the window: the whole of
    /// the status bar is over it.
    @Test("A page under the status bar is covered as deep as the status bar goes")
    func aPageUnderTheStatusBar() {
        let page = CGRect(x: 0, y: 0, width: 402, height: 840)
        let statusBar = CGRect(x: 0, y: 0, width: 402, height: 62)
        #expect(MarkdownTextView.room(above: page, coveredBy: statusBar) == 62)
    }

    /// The page a notice has the top of starts below the notice, and so below
    /// the status bar: there is nothing under the clock to soften.
    @Test("A page that starts below the status bar has no band")
    func aPageBelowTheStatusBar() {
        let page = CGRect(x: 0, y: 150, width: 402, height: 690)
        let statusBar = CGRect(x: 0, y: 0, width: 402, height: 62)
        #expect(MarkdownTextView.room(above: page, coveredBy: statusBar) == 0)
    }

    /// A window with no status bar — a phone on its side — has a status bar of
    /// no height, and no band either.
    @Test("No status bar is no band")
    func noStatusBar() {
        let page = CGRect(x: 0, y: 0, width: 874, height: 402)
        let statusBar = CGRect(x: 0, y: 0, width: 874, height: 0)
        #expect(MarkdownTextView.room(above: page, coveredBy: statusBar) == 0)
    }
}
