import AujourCore
import SwiftUI
import Testing
import UIKit

@testable import Aujour

// The identity's foundation, held to the two things that make it a foundation
// rather than a mood board: every colour clears ADR 0006's floor on every
// ground it can land on, and every size grows when the reader turns the system
// text up.
//
// Headless. A colour can be asked what it came out as and a font what size it
// ended up, so neither of these needs a screenshot — what a *screen* built out
// of them looks like at the largest accessibility size is the UI suite's, and
// is asked there.

/// Everything opaque that the identity draws a word onto. The floor is not a
/// property of an ink on its own — the same near-black is 2.28:1 on paper and
/// 4.10:1 on a dark card — so every measurement here names one of these.
private let grounds: [(name: String, colour: UIColor)] = [
    ("background", Palette.background),
    ("card", Palette.card),
    ("sheet", Palette.sheet),
    ("glass", Palette.glassSolid),
]

private let appearances: [(name: String, style: UIUserInterfaceStyle)] = [
    ("light", .light), ("dark", .dark),
]

@MainActor
@Suite("The identity's palette")
struct PaletteTests {
    @Test("the grounds are the identity's own paper, in both appearances")
    func groundsAreTheIdentitys() {
        #expect(Palette.background.hex(in: .light) == "#F6F2EC")
        #expect(Palette.background.hex(in: .dark) == "#16130F")
        #expect(Palette.card.hex(in: .light) == "#FFFEFC")
        #expect(Palette.card.hex(in: .dark) == "#292520")
        #expect(Palette.sheet.hex(in: .light) == "#FBF8F2")
        #expect(Palette.sheet.hex(in: .dark) == "#1B1712")
        #expect(Palette.ink.hex(in: .light) == "#241F1B")
        #expect(Palette.ink.hex(in: .dark) == "#F2EDE5")
    }

    /// The one that would go unnoticed: a token written as a plain colour
    /// rather than a dynamic one looks perfectly right in whichever appearance
    /// it was written in, and is invisible in the other.
    ///
    /// Alpha counts as turning. `glassHighlight` is white in both and would
    /// have to be — a lit edge is light — and what changes is how much of it
    /// there is, `.70` on paper against `.16` on near-black.
    @Test("no token is the same in light and in dark")
    func everyTokenTurnsWithTheAppearance() {
        for (name, colour) in Palette.everyToken {
            #expect(
                colour.resolved(in: .light) != colour.resolved(in: .dark),
                "\(name) is \(colour.resolved(in: .light)) in both appearances"
            )
        }
    }

    /// The third appearance, which is not a third set of values. "Auto" is the
    /// app declining to override anything, so a token under it is whatever the
    /// screen it landed on is — which the two tests above already cover, one
    /// screen at a time.
    ///
    /// What is left to ask is the case with no screen to speak of: a trait
    /// collection that specifies no appearance at all. A token has to answer
    /// that with the light value, and the failure mode is silent — a `switch`
    /// over the three cases with a `default` returning `.clear`, or a token
    /// that read the stored theme instead of the traits, both come out as
    /// nothing here and as something everywhere else.
    @Test("a token asked without an appearance answers in the light one")
    func tokensResolveWithNoAppearanceSpecified() {
        let noAppearance = UITraitCollection(userInterfaceStyle: .unspecified)
        for (name, colour) in Palette.everyToken {
            let auto = colour.resolvedColor(with: noAppearance)
            var alpha: CGFloat = 0
            auto.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            #expect(alpha > 0, "\(name) resolves to nothing when no appearance is specified")
            #expect(
                auto.resolved(in: .light) == colour.resolved(in: .light),
                """
                \(name) under no appearance is \(auto.resolved(in: .light)), where a light \
                screen gets \(colour.resolved(in: .light))
                """
            )
        }
    }

    /// ADR 0006's floor, for the inks that carry sentences: the ink itself and
    /// the muted step under it. Between them they carry every sentence the app
    /// says about itself.
    @Test("an ink a sentence is written in clears 4.5:1 wherever it lands", arguments: appearances)
    func sentenceInksClearTheFloor(appearance: (name: String, style: UIUserInterfaceStyle)) {
        for (inkName, ink) in [("ink", Palette.ink), ("inkMuted", Palette.inkMuted)] {
            for ground in grounds {
                let measured = Landed(ink, in: appearance.style, over: ground.colour)
                    .contrast(against: Landed(ground.colour, in: appearance.style))
                #expect(
                    measured >= 4.5,
                    "\(inkName) on \(ground.name) in \(appearance.name) is \(measured), under 4.5:1"
                )
            }
        }
    }

    /// And the floor for the faint step, which is markers, chevrons and the
    /// small capitals over a section — never a sentence. That is the whole
    /// reason there are three inks and not two: held to 4.5:1 the faint step
    /// would land on top of the muted one and the identity would have lost a
    /// step it uses.
    @Test("the faint ink clears the marker floor of 3:1", arguments: appearances)
    func theFaintInkClearsTheMarkerFloor(appearance: (name: String, style: UIUserInterfaceStyle)) {
        for ground in grounds {
            let measured = Landed(Palette.inkFaint, in: appearance.style, over: ground.colour)
                .contrast(against: Landed(ground.colour, in: appearance.style))
            #expect(
                measured >= 3,
                "inkFaint on \(ground.name) in \(appearance.name) is \(measured), under 3:1"
            )
        }
    }

    /// The one colour in the palette that is neither paper, ink nor accent.
    /// It carries a sentence — the whole of what an alarm is here is a
    /// sentence saying what has gone wrong — so it is held to the sentence
    /// floor on every ground, which is what the system's own red does not
    /// clear on paper.
    @Test("the alarm clears 4.5:1 wherever a sentence in it lands", arguments: appearances)
    func theAlarmClearsTheSentenceFloor(appearance: (name: String, style: UIUserInterfaceStyle)) {
        for ground in grounds {
            let measured = Landed(Palette.alarm, in: appearance.style, over: ground.colour)
                .contrast(against: Landed(ground.colour, in: appearance.style))
            #expect(
                measured >= 4.5,
                "alarm on \(ground.name) in \(appearance.name) is \(measured), under 4.5:1"
            )
        }
    }

    /// And that it is the identity's own and not the system's, which is the
    /// value it replaced and the reason the token exists: `.systemRed` reads
    /// at 3.18:1 on the paper Aujour draws on.
    @Test("the alarm is not the system's red")
    func theAlarmIsTheIdentitysOwn() {
        #expect(Palette.alarm.hex(in: .light) != UIColor.systemRed.hex(in: .light))
        let systemRed = Landed(.systemRed, in: .light, over: Palette.background)
            .contrast(against: Landed(Palette.background, in: .light))
        #expect(systemRed < 4.5, "the system's red clears the floor — this token is unnecessary")
    }

    /// The step has to be visible, or the palette is claiming a distinction it
    /// does not draw.
    @Test("the three inks are three different colours", arguments: appearances)
    func theThreeInksAreThreeSteps(appearance: (name: String, style: UIUserInterfaceStyle)) {
        let over = Palette.background
        let steps = [Palette.ink, Palette.inkMuted, Palette.inkFaint].map {
            Landed($0, in: appearance.style, over: over)
                .contrast(against: Landed(over, in: appearance.style))
        }
        #expect(steps[0] > steps[1], "the muted ink is not quieter than the ink")
        #expect(steps[1] > steps[2] + 1, "the faint ink is barely quieter than the muted one")
    }
}

@MainActor
@Suite("Every accent, held to the floor")
struct AccentContrastTests {
    /// An accent is a word as often as it is a shape — a settings row's value,
    /// the way back out of a sheet — so the colour itself is held to the
    /// sentence floor and not the marker one (ADR 0006).
    @Test("every accent clears 4.5:1 as text on every ground", arguments: Accent.allCases)
    func accentsClearTheFloorAsText(accent: Accent) {
        for appearance in appearances {
            for ground in grounds {
                let measured = Landed(accent.uiColor, in: appearance.style)
                    .contrast(against: Landed(ground.colour, in: appearance.style))
                #expect(
                    measured >= 4.5,
                    """
                    \(accent.name) on \(ground.name) in \(appearance.name) is \(measured), \
                    under 4.5:1
                    """
                )
            }
        }
    }

    /// The case the accent alone cannot cover: the identity tints a pill with
    /// the accent and then writes on it in the accent, and a colour on a wash
    /// of itself loses about a point of contrast. That is what the ink shade
    /// is for, so it is held to the floor on the wash *and* on bare paper.
    @Test("every accent's ink clears 4.5:1 on a wash of that accent", arguments: Accent.allCases)
    func accentInkClearsTheFloorOnItsOwnWash(accent: Accent) {
        for appearance in appearances {
            for ground in grounds {
                let wash = Landed(accent.softColor, in: appearance.style, over: ground.colour)
                let ink = Landed(accent.inkColor, in: appearance.style)
                #expect(
                    ink.contrast(against: wash) >= 4.5,
                    """
                    \(accent.name)'s ink on its wash over \(ground.name) in \(appearance.name) \
                    is \(ink.contrast(against: wash)), under 4.5:1
                    """
                )
                #expect(
                    ink.contrast(against: Landed(ground.colour, in: appearance.style)) >= 4.5,
                    """
                    \(accent.name)'s ink on bare \(ground.name) in \(appearance.name) is \
                    under 4.5:1
                    """
                )
            }
        }
    }

    /// The other way round: a mark written *on* a fill of the accent rather
    /// than in it, which is the pressed key on the accessory row and the only
    /// place in the app that happens. `Palette.onAccent` is the paper of the
    /// appearance the accent was tuned against — near-white in light, where
    /// the accents are dark enough to carry it, near-black in dark, where they
    /// are light.
    ///
    /// Held to 4.5:1 and not the 3:1 a mark could settle for, because all nine
    /// clear it with room and a floor nobody is pressed against is a floor
    /// worth keeping.
    @Test("what is written on a fill of the accent clears 4.5:1", arguments: Accent.allCases)
    func onAccentClearsTheFloorOnTheAccent(accent: Accent) {
        for appearance in appearances {
            let fill = Landed(accent.uiColor, in: appearance.style)
            let mark = Landed(Palette.onAccent, in: appearance.style, over: accent.uiColor)
            #expect(
                mark.contrast(against: fill) >= 4.5,
                """
                a mark on \(accent.name) in \(appearance.name) is \
                \(mark.contrast(against: fill)), under 4.5:1
                """
            )
        }
    }

    @Test("each accent is a different colour in light and in dark", arguments: Accent.allCases)
    func accentsTurnWithTheAppearance(accent: Accent) {
        #expect(accent.uiColor.hex(in: .light) != accent.uiColor.hex(in: .dark))
        #expect(accent.inkColor.hex(in: .light) != accent.inkColor.hex(in: .dark))
    }

    /// A wash is a wash: opaque, it would be a second set of nine colours to
    /// keep in step with the first.
    @Test("the washes are the accent, thinned", arguments: Accent.allCases)
    func washesAreTheAccentThinned(accent: Accent) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            var softAlpha: CGFloat = 0
            var softerAlpha: CGFloat = 0
            accent.softColor.resolvedColor(with: traits)
                .getRed(nil, green: nil, blue: nil, alpha: &softAlpha)
            accent.softerColor.resolvedColor(with: traits)
                .getRed(nil, green: nil, blue: nil, alpha: &softerAlpha)
            #expect(softAlpha < 1 && softAlpha > 0)
            #expect(softerAlpha > softAlpha)
        }
    }
}

@MainActor
@Suite("Newsreader, the identity's prose voice")
struct NewsreaderTests {
    @Test("every weight the identity uses is on the device", arguments: Newsreader.Weight.allCases)
    func everyWeightIsBundled(weight: Newsreader.Weight) {
        for slant in [Newsreader.Slant.roman, .italic] {
            let font = Newsreader.face(weight, slant, size: 17)
            #expect(
                font.familyName == "Newsreader",
                """
                \(weight) \(slant) fell back to \(font.familyName) — Newsreader is not \
                registered, or the name in UIAppFonts is wrong
                """
            )
        }
    }

    /// A variable font that fell back to its default instance registers fine,
    /// resolves fine and draws every weight identically. The axis is the only
    /// thing that says otherwise.
    @Test("the weights are actually different weights")
    func theWeightsAreDistinct() {
        let widths = Newsreader.Weight.allCases.map { weight in
            let font = Newsreader.face(weight, .roman, size: 40)
            return ("Handwriting" as NSString).size(withAttributes: [.font: font]).width
        }
        #expect(widths == widths.sorted(), "a heavier weight did not set wider")
        #expect(Set(widths).count == widths.count, "two weights set identically")
    }

    @Test("the italic is a different face from the roman")
    func theItalicIsItalic() {
        let roman = Newsreader.face(.regular, .roman, size: 24)
        let italic = Newsreader.face(.regular, .italic, size: 24)
        #expect(roman.fontName != italic.fontName)
        #expect(italic.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    @Test("the licence travels with the font")
    func theLicenceIsBundled() {
        #expect(Bundle.main.url(forResource: "Newsreader-OFL", withExtension: "txt") != nil)
    }
}

@MainActor
@Suite("The type scale")
struct LetteringTests {
    /// The whole point of the scale. Chrome answers Dynamic Type — every one
    /// of these, and not a subset, because the one that does not is the row a
    /// reader who turned the text up cannot read.
    @Test("every size on the scale grows with Dynamic Type", arguments: Lettering.everyRole)
    func chromeGrowsWithDynamicType(role: (name: String, lettering: Lettering)) {
        let factory = role.lettering.uiFont(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let turnedUp = role.lettering.uiFont(
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
            )
        )
        let turnedDown = role.lettering.uiFont(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraSmall)
        )
        #expect(
            turnedUp.pointSize > factory.pointSize,
            "\(role.name) did not grow when the system text size did"
        )
        // The other direction is asked as "never larger" rather than as
        // "smaller", because iOS itself declines to go under 11 points for its
        // smallest text styles — a role that grows with `.caption2` is 11
        // points at every setting from the smallest up to the factory one, and
        // that is the system's table and not this scale being pinned.
        #expect(
            turnedDown.pointSize <= factory.pointSize,
            "\(role.name) got bigger as the system text size got smaller"
        )
    }

    /// The seam between the size SwiftUI hands a view and the size
    /// `UIFontMetrics` scales against. Every step has to map to a distinct one
    /// and they have to be in the same order, or the slider would have flat
    /// spots or run backwards somewhere in the middle where nobody looks.
    @Test("every step of the system's slider maps to a step of UIKit's")
    func everyDynamicTypeSizeHasAContentSize() {
        let mapped = DynamicTypeSize.allCases.map(\.contentSize)
        #expect(Set(mapped).count == mapped.count, "two steps map to the same size")

        let grown = mapped.map {
            Lettering.rowLabel
                .uiFont(compatibleWith: UITraitCollection(preferredContentSizeCategory: $0))
                .pointSize
        }
        #expect(grown == grown.sorted(), "the steps do not come out in order: \(grown)")
        #expect(grown.first! < grown.last!, "the largest step is no bigger than the smallest")
    }

    @Test("the scale has steps a reader can tell apart")
    func theScaleHasSteps() {
        let factory = UITraitCollection(preferredContentSizeCategory: .large)
        #expect(
            Lettering.screenTitle.uiFont(compatibleWith: factory).pointSize
                > Lettering.sheetTitle.uiFont(compatibleWith: factory).pointSize
        )
        #expect(
            Lettering.sheetTitle.uiFont(compatibleWith: factory).pointSize
                > Lettering.rowLabel.uiFont(compatibleWith: factory).pointSize
        )
        #expect(
            Lettering.rowLabel.uiFont(compatibleWith: factory).pointSize
                > Lettering.rowValue.uiFont(compatibleWith: factory).pointSize
        )
        #expect(
            Lettering.rowValue.uiFont(compatibleWith: factory).pointSize
                > Lettering.sectionHeader.uiFont(compatibleWith: factory).pointSize
        )
    }

    @Test("the prose roles are set in Newsreader and the chrome roles are not")
    func proseIsNewsreader() {
        for role in Lettering.everyRole {
            let family = role.lettering.uiFont(compatibleWith: nil).familyName
            if role.lettering.isProse {
                #expect(family == "Newsreader", "\(role.name) is prose but is set in \(family)")
            } else {
                #expect(family != "Newsreader", "\(role.name) is chrome but is set in Newsreader")
            }
        }
    }

    /// The line the whole redesign turns on: the in-app S/M/L/XL control is a
    /// writing preference and reaches the Entry alone, so nothing on the scale
    /// may move when it changes (`CONTEXT.md`, Device Settings).
    @Test("the editor's own size control moves nothing on the scale")
    func theEditorsSizeControlStaysOutOfTheChrome() {
        let factory = UITraitCollection(preferredContentSizeCategory: .large)
        let before = Lettering.everyRole.map {
            $0.lettering.uiFont(compatibleWith: factory).pointSize
        }

        let appearance = DeviceAppearance.inMemory()
        appearance.useEditorFont(sized: .extraLarge)
        appearance.useEditorFont(.serif)

        let after = Lettering.everyRole.map {
            $0.lettering.uiFont(compatibleWith: factory).pointSize
        }
        #expect(before == after)
    }
}
