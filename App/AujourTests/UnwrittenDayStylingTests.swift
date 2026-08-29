import AujourCore
import Foundation
import Testing
import UIKit

@testable import Aujour

// A day nobody has written is drawn quieter than one somebody has, and that is
// the whole of what tells them apart on screen: a day with no file is spawned
// from the Content Template exactly as today is, so it arrives headings and
// all, looking like a day somebody wrote.
//
// The look is a value, so this needs no screenshot. What it has to hold is that
// the two are *different* — a quiet step that came out identical to the loud
// one would be a distinction the app was making and nobody could see — and that
// the difference is only the words. Whether the quiet step is readable is
// `IdentityTests`, which holds every ink a sentence is written in to 4.5:1 on
// every ground the app draws on.

@Suite("How a day nobody has written is drawn")
struct UnwrittenDayStylingTests {
    private let written = MarkdownStyling(
        body: .preferredFont(forTextStyle: .body),
        link: Accent.driftwood.uiColor,
        box: Accent.driftwood.uiColor
    )

    /// The step the identity keeps for markers and for a field's placeholder,
    /// which is what a Content Template spawned into a day with no file is:
    /// not somebody's prose, but what stands in the Entry until they write it.
    ///
    /// Below the sentence floor on purpose, and `IdentityTests` holds it to
    /// the marker floor it *is* held to. What makes that the right side of the
    /// line is that nothing drawn in it is the reader's own — the first
    /// keystroke takes the page to the full ink, so no word anybody wrote is
    /// ever drawn this quietly.
    @Test("its words are the faint ink, which is the step a placeholder takes")
    func theWordsTakeTheFaintInk() {
        #expect(written.forADayNobodyHasWritten.words == Palette.inkFaint)
    }

    /// The reader's own words are never drawn below the sentence floor, which
    /// is the promise the step above buys its quiet with.
    @Test("a day somebody has written is not drawn in it")
    func awrittenDayKeepsTheFullInk() {
        #expect(written.words != Palette.inkFaint)
        #expect(written.words != Palette.inkMuted)
    }

    /// The distinction has to be visible, which means the two stylings cannot
    /// resolve to the same colour in either appearance.
    @Test("a written day and an unwritten one are not the same colour")
    func theTwoStepsAreTwoSteps() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let loud = written.words.resolvedColor(with: traits)
            let quiet = written.forADayNobodyHasWritten.words.resolvedColor(with: traits)

            #expect(loud != quiet, "the two steps came out the same colour in \(style)")
        }
    }

    /// Only the words. A link is still a link and a task's box is still a
    /// control — both drawn in the accent this device chose, and both held to a
    /// floor of their own.
    ///
    /// Which does leave the marks and the words at one step on an unwritten
    /// day: there is nothing under the faint one to move the marks to. The
    /// distinction comes back at the first keystroke, with the reason to want
    /// it.
    @Test("nothing but the words is touched")
    func onlyTheWordsMove() {
        let quieter = written.forADayNobodyHasWritten

        #expect(quieter.body == written.body)
        #expect(quieter.syntax == written.syntax)
        #expect(quieter.quoted == written.quoted)
        #expect(quieter.link == written.link)
        #expect(quieter.box == written.box)
        #expect(quieter.lineSpacing == written.lineSpacing)
    }

    /// What the editor re-draws on. It compares the styling in force against
    /// the one wanted by font, accent and words, and a difference it could not
    /// see is a day that stayed quiet after it had been written into.
    @Test("the two stylings are not equal, which is what makes the editor redraw")
    func theEditorCanTellThemApart() {
        #expect(written.forADayNobodyHasWritten != written)
    }
}
