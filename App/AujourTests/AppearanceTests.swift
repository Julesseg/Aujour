import AujourCore
import SwiftUI
import Testing
import UIKit

@testable import Aujour

// What theming is once there is a screen to draw it on. Which appearance,
// which accent and which typeface the user chose — and that none of it
// travels — is Core's and is proved there; what is left here is the half that
// needs UIKit to mean anything: that "serif" is a serif, that a size the user
// asked for is the size they get, that Dynamic Type still moves it, and that
// six named accents are six colours a user can tell apart in light and in
// dark.
//
// Headless, and no simulator screenshot in sight: a font and a colour can both
// be asked what they came out as.

@MainActor
@Suite("How Aujour looks on this device")
struct DeviceAppearanceTests {
    @Test("each theme is the colour scheme it names, and the system one overrides nothing")
    func themesBecomeColourSchemes() {
        let appearance = DeviceAppearance.inMemory()

        appearance.use(.light)
        #expect(appearance.colorScheme == .light)

        appearance.use(.dark)
        #expect(appearance.colorScheme == .dark)

        // The default, and the only one of the three that is not an
        // instruction: nil leaves the device's own appearance alone.
        appearance.use(.system)
        #expect(appearance.colorScheme == nil)
    }

    @Test("what was chosen here is still chosen after a relaunch")
    func choicesSurviveARelaunch() {
        let onThisDevice = InMemoryLocalKeyValueStore()

        let appearance = DeviceAppearance(settings: DeviceSettingsStore(storedOn: onThisDevice))
        appearance.use(.dark)
        appearance.use(.moss)
        appearance.useEditorFont(.serif)
        appearance.useEditorFont(sized: 22)

        let afterRelaunch = DeviceAppearance(
            settings: DeviceSettingsStore(storedOn: onThisDevice)
        )
        #expect(afterRelaunch.theme == .dark)
        #expect(afterRelaunch.accent == .moss)
        #expect(afterRelaunch.editorFont == EditorFont(family: .serif, size: 22))
    }

    @Test("a size the editor could not render is refused rather than stored")
    func sizesStayInRange() {
        let appearance = DeviceAppearance.inMemory()

        appearance.useEditorFont(sized: 100)

        #expect(EditorFont.sizeRange.contains(appearance.editorFont.size))
    }

    @Test("the editor is told about a change the moment it is made")
    func theEditorSeesChangesLive() {
        let appearance = DeviceAppearance.inMemory()
        #expect(appearance.editorLook == EditorLook(font: .default, accent: .ink))

        appearance.use(.rose)
        appearance.useEditorFont(.monospaced)

        #expect(
            appearance.editorLook
                == EditorLook(
                    font: EditorFont(family: .monospaced, size: EditorFont.default.size),
                    accent: .rose
                )
        )
    }
}

@MainActor
@Suite("The accent, as a colour")
struct AccentColourTests {
    @Test("every accent is a different colour, in light and in dark")
    func accentsAreTellableApart() {
        for scheme in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: scheme)
            let drawn = Accent.allCases.map { $0.uiColor.resolvedColor(with: traits) }

            for (one, another) in pairs(of: Accent.allCases) {
                #expect(
                    one.uiColor.resolvedColor(with: traits)
                        != another.uiColor.resolvedColor(with: traits),
                    "\(one) and \(another) are the same colour in \(scheme.rawValue)"
                )
            }
            #expect(drawn.count == Accent.allCases.count)
        }
    }

    @Test("an accent is drawn differently in light and in dark, so it reads on either page")
    func accentsAnswerTheAppearance() {
        for accent in Accent.allCases {
            let inLight = accent.uiColor.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .light)
            )
            let inDark = accent.uiColor.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .dark)
            )
            #expect(inLight != inDark, "\(accent) is the same colour on both pages")
        }
    }

    @Test("an accent asked for twice is the same colour, so a restyle can tell nothing changed")
    func theSameAccentIsTheSameColour() {
        // The editor redraws a whole day when the colour it is drawing in
        // stops being the one it was drawing in. Two freshly built dynamic
        // colours would never compare equal, so every keystroke would restyle
        // thousands of words.
        #expect(Accent.plum.uiColor == Accent.plum.uiColor)
        #expect(Accent.plum.uiColor != Accent.sea.uiColor)
    }

    @Test("every accent has a name to offer it by")
    func accentsAreNamed() {
        for accent in Accent.allCases {
            #expect(!accent.name.isEmpty)
        }
        #expect(Set(Accent.allCases.map(\.name)).count == Accent.allCases.count)
    }

    private func pairs(of accents: [Accent]) -> [(Accent, Accent)] {
        accents.enumerated().flatMap { index, one in
            accents.dropFirst(index + 1).map { (one, $0) }
        }
    }
}

@MainActor
@Suite("The editor's typeface")
struct EditorTypefaceTests {
    private let unmoved = UITraitCollection(preferredContentSizeCategory: .large)

    @Test("the size the user chose is the size the editor draws at")
    func theChosenSizeIsTheSizeDrawn() {
        let font = EditorFont(family: .system, size: 22).uiFont(compatibleWith: unmoved)

        #expect(font.pointSize == 22)
    }

    @Test("each family is the kind of typeface it names")
    func familiesAreWhatTheyAreCalled() {
        let system = EditorFont(family: .system, size: 17).uiFont(compatibleWith: unmoved)
        let serif = EditorFont(family: .serif, size: 17).uiFont(compatibleWith: unmoved)
        let monospaced = EditorFont(family: .monospaced, size: 17).uiFont(compatibleWith: unmoved)

        #expect(serif.familyName != system.familyName)
        #expect(monospaced.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        #expect(!system.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
    }

    @Test("the same choice is the same font twice over, so a keystroke restyles nothing")
    func theSameChoiceIsTheSameFont() {
        // The other half of what keeps the editor from redrawing a long day
        // on every keystroke: the font it compares against has to come out
        // equal when nothing has moved.
        let chosen = EditorFont(family: .serif, size: 19)

        #expect(chosen.uiFont(compatibleWith: unmoved) == chosen.uiFont(compatibleWith: unmoved))
    }

    @Test("Dynamic Type still moves a size the user chose")
    func dynamicTypeStillReaches() {
        let chosen = EditorFont(family: .serif, size: 17)

        let large = chosen.uiFont(compatibleWith: unmoved)
        let accessible = chosen.uiFont(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityLarge)
        )

        #expect(accessible.pointSize > large.pointSize)
        #expect(accessible.familyName == large.familyName)
    }
}
