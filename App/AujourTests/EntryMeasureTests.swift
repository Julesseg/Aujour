import AujourCore
import Foundation
import Testing
import UIKit

@testable import Aujour

/// The width a day's words are set at when the window is wide enough that
/// there is a choice — which is the whole of what the sidebar layout does to
/// the Entry.
///
/// A measure is counted in characters and not in points, so the number of
/// points is the reader's own face's answer to that count: a monospaced day is
/// set wider than a sans one, and a reader who has turned the text up is set
/// wider again. Held here rather than in a screenshot because the thing worth
/// proving is that a line really does come out around 65 characters long, and
/// that is a layout measurement.
@MainActor
@Suite("The measure a day is set at")
struct EntryMeasureTests {
    /// Prose rather than an alphabet: what the measure has to be right about
    /// is the width of real writing, and a line of `abcdefghij…` is not a
    /// sample of anybody's day.
    private static let prose = """
        Woke before the alarm and lay there listening to the rain come off the \
        gutter. Made coffee, read a page, gave up on the page. The morning went \
        somewhere without asking me first, and by the time I looked up the light \
        had gone flat and grey and the whole street smelled of wet leaves. Walked \
        to the bridge anyway. Came back the long way, past the bakery that never \
        opens, and stood in the hall a while with my coat still on.
        """

    /// How many characters a line of that prose comes out at, set at a given
    /// look's own measure.
    private func charactersPerLine(of look: EditorLook) -> Double {
        let day = LaidOutDay(
            Self.prose,
            styling: look.styling(compatibleWith: nil),
            width: look.measure(compatibleWith: nil)
        )
        let lines = day.lineFragments().count
        return Double(Self.prose.count) / Double(lines)
    }

    /// The one thing the number is for. Not to the character — where a line
    /// breaks is the word's business and the last line is however long the
    /// paragraph ran out at — but a measure that came out at forty or at ninety
    /// would be a different decision than the one that was made.
    @Test(
        "a day set at the measure comes out around 65 characters a line",
        arguments: [
            EditorFont.Family.system, .serif, .monospaced,
        ]
    )
    func aLineIsAroundSixtyFiveCharacters(family: EditorFont.Family) {
        let look = EditorLook(font: EditorFont(family: family, size: .medium), accent: .driftwood)

        let characters = charactersPerLine(of: look)

        #expect(
            characters > 55 && characters < 80,
            "\(family) set \(characters) characters a line"
        )
    }

    /// The measure is the reader's face's answer and not a number typed in:
    /// the same 65 characters take more room in a monospaced face than in a
    /// proportional one, and a page capped at one width for both would be set
    /// long in one of them.
    @Test("a monospaced day is set wider than a proportional one")
    func theFaceDecidesHowWideTheMeasureIs() {
        let mono = EditorLook(font: EditorFont(family: .monospaced, size: .medium), accent: .olive)
        let sans = EditorLook(font: EditorFont(family: .system, size: .medium), accent: .olive)

        #expect(mono.measure(compatibleWith: nil) > sans.measure(compatibleWith: nil))
    }

    /// And it is the size the reader chose, for the same reason: a larger step
    /// is larger letters, so 65 of them need more room.
    @Test("a larger step is set wider, so the count stays the same")
    func theSizeStepMovesTheMeasure() {
        let steps = EditorFont.Size.allCases.sorted { $0.points < $1.points }

        let measures = steps.map {
            EditorLook(font: EditorFont(family: .system, size: $0), accent: .olive)
                .measure(compatibleWith: nil)
        }

        #expect(measures == measures.sorted())
        #expect(measures.first! < measures.last!)
    }

    /// Dynamic Type moves it too, which is the same rule said for the setting
    /// that is not Aujour's: somebody who has turned the system's text up has
    /// turned up the letters this is counting.
    @Test("a reader who has turned the text up is set wider")
    func dynamicTypeMovesTheMeasure() {
        let look = EditorLook.default

        let atTheFactorySetting = look.measure(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let turnedUp = look.measure(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityLarge)
        )

        #expect(turnedUp > atTheFactorySetting)
    }
}
