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
        appearance.use(.olive)
        appearance.useEditorFont(.serif)
        appearance.useEditorFont(sized: .extraLarge)

        let afterRelaunch = DeviceAppearance(
            settings: DeviceSettingsStore(storedOn: onThisDevice)
        )
        #expect(afterRelaunch.theme == .dark)
        #expect(afterRelaunch.accent == .olive)
        #expect(afterRelaunch.editorFont == EditorFont(family: .serif, size: .extraLarge))
    }

    @Test("every step is a bigger size than the one before it")
    func stepsGetBigger() {
        let unmoved = UITraitCollection(preferredContentSizeCategory: .large)
        let drawn = EditorFont.Size.allCases.map {
            EditorFont(family: .system, size: $0).uiFont(compatibleWith: unmoved).pointSize
        }

        #expect(drawn == drawn.sorted())
        #expect(Set(drawn).count == drawn.count)
    }

    @Test("the editor is told about a change the moment it is made")
    func theEditorSeesChangesLive() {
        let appearance = DeviceAppearance.inMemory()
        #expect(appearance.editorLook == EditorLook(font: .default, accent: .driftwood))

        appearance.use(.clay)
        appearance.useEditorFont(.monospaced)

        #expect(
            appearance.editorLook
                == EditorLook(
                    font: EditorFont(family: .monospaced, size: EditorFont.default.size),
                    accent: .clay
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
        #expect(Accent.plum.uiColor != Accent.sage.uiColor)
    }

    @Test("every accent clears the contrast floor it is held to (ADR 0006)")
    func accentsAreLegibleOnTheGroundTheyAreDrawnOn() {
        // The identity's own grounds: the sheet an accent is drawn as text on
        // in light, and the page behind everything in dark. 4.5:1 is what a
        // sentence has to clear, and an accent here carries sentences.
        let grounds: [(UIUserInterfaceStyle, UIColor)] = [
            (.light, UIColor(red: 0xFB / 255, green: 0xF8 / 255, blue: 0xF2 / 255, alpha: 1)),
            (.dark, UIColor(red: 0x16 / 255, green: 0x13 / 255, blue: 0x0F / 255, alpha: 1)),
        ]

        for (style, ground) in grounds {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for accent in Accent.allCases {
                let contrast = accent.uiColor.resolvedColor(with: traits).contrast(against: ground)
                #expect(
                    contrast >= 4.5,
                    "\(accent.name) reads at \(contrast):1 in \(style.rawValue), under the floor"
                )
            }
        }
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
        let font = EditorFont(family: .system, size: .extraLarge).uiFont(compatibleWith: unmoved)

        #expect(font.pointSize == EditorFont.Size.extraLarge.points)
    }

    @Test("each family is the kind of typeface it names")
    func familiesAreWhatTheyAreCalled() {
        let system = EditorFont(family: .system, size: .medium).uiFont(compatibleWith: unmoved)
        let serif = EditorFont(family: .serif, size: .medium).uiFont(compatibleWith: unmoved)
        let monospaced = EditorFont(family: .monospaced, size: .medium).uiFont(compatibleWith: unmoved)

        #expect(serif.familyName != system.familyName)
        #expect(monospaced.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        #expect(!system.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
    }

    @Test("the same choice is the same font twice over, so a keystroke restyles nothing")
    func theSameChoiceIsTheSameFont() {
        // The other half of what keeps the editor from redrawing a long day
        // on every keystroke: the font it compares against has to come out
        // equal when nothing has moved.
        let chosen = EditorFont(family: .serif, size: .large)

        #expect(chosen.uiFont(compatibleWith: unmoved) == chosen.uiFont(compatibleWith: unmoved))
    }

    @Test("Dynamic Type still moves a size the user chose")
    func dynamicTypeStillReaches() {
        let chosen = EditorFont(family: .serif, size: .medium)

        let large = chosen.uiFont(compatibleWith: unmoved)
        let accessible = chosen.uiFont(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityLarge)
        )

        #expect(accessible.pointSize > large.pointSize)
        #expect(accessible.familyName == large.familyName)
    }
}

extension UIColor {
    /// WCAG relative contrast against another colour, which is the whole of
    /// what "held to a floor" means (ADR 0006).
    fileprivate func contrast(against other: UIColor) -> Double {
        let mine = relativeLuminance
        let theirs = other.relativeLuminance
        return (max(mine, theirs) + 0.05) / (min(mine, theirs) + 0.05)
    }

    private var relativeLuminance: Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

@Suite("The screen the appearance is chosen on")
struct AppearanceScreenTests {
    @Test("every theme there is can be picked, auto included")
    func everyThemeIsOnTheControl() {
        // Auto above all, which has been in the model since the beginning
        // and had no screen able to select it: a theme the store can hold and
        // the control cannot offer is a setting the user can only arrive at
        // by accident.
        #expect(Set(Theme.asOffered) == Set(Theme.allCases))
        // And each of them once, so a duplicate cannot stand in for a missing
        // one and still make the set match.
        #expect(Theme.asOffered.count == Theme.allCases.count)
    }

    @Test("auto is offered after the two that are instructions")
    func autoComesLast() {
        // The order the design file's own segmented control reads in
        // (`docs/design/identity/Aujour.dc.html`, the Appearance sheet), and
        // the order the two kinds fall into: light and dark say what to do,
        // auto says who decides.
        #expect(Theme.asOffered == [.light, .dark, .system])
    }
}

@Suite("The editor's size control governs the Entry alone")
struct WritingPreferenceReachTests {
    /// Where the app's own sources are, from this file.
    private var appSources: URL {
        URL(filePath: #filePath)  // App/AujourTests/<this file>
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Aujour")
    }

    /// The six files the editor's own typeface is allowed to pass through:
    /// where it is defined, where it is made, where it is put into the
    /// environment, the control that chooses it, and the two that draw the
    /// Entry's own words with it.
    ///
    /// A list and not a rule, because what is being held is an absence:
    /// S/M/L/XL is a *writing* preference, and chrome that quietly started
    /// following it would look correct on every screen and be wrong on the
    /// one where the reader has turned the system's text size up
    /// (`CONTEXT.md`, Device Settings; `Lettering`).
    ///
    /// By the path each lives at and not by its name, because the walk below
    /// is recursive: a second `EntryView.swift` under a subfolder would
    /// otherwise be exempt by coincidence. A test below holds every one of
    /// these to a file that is really there, so a rename cannot leave an
    /// exemption behind for a file nobody has to look at again.
    private let mayDrawInIt: Set<String> = [
        "Appearance.swift",  // defines EditorLook and the environment key
        "DeviceAppearance.swift",  // answers with the one in force
        "AujourApp.swift",  // puts it in the environment, once
        "AppearanceSettingsView.swift",  // the control choosing it, and its specimen
        "EntryView.swift",  // the prompt over a day nobody has written
        "Editor/MarkdownEditor.swift",  // draws the day in it
    ]

    /// Both names the choice travels under: the value the environment carries,
    /// and the stored preference underneath it. Lowercased, so that one term
    /// catches the type and the property alike.
    private let namesItTravelsUnder = ["editorlook", "editorfont"]

    @Test("nothing but the editor is drawn in what the editor is drawn in")
    func onlyTheEditorFollowsTheWritingPreference() throws {
        let elsewhere = try swiftSources(in: appSources)
            .filter { !mayDrawInIt.contains($0.path) }

        for source in elsewhere {
            let text = try String(contentsOf: source.url, encoding: .utf8).lowercased()
            for name in namesItTravelsUnder {
                #expect(
                    !text.contains(name),
                    """
                    \(source.path) is drawn in the editor's own font; the S/M/L/XL control \
                    is a writing preference and reaches the Entry alone. Everything else \
                    follows the system's text size, through `Lettering`.
                    """
                )
            }
        }
    }

    @Test("every file excused above is a file that is still there")
    func theExemptionsAreHonest() throws {
        let present = Set(try swiftSources(in: appSources).map(\.path))

        for excused in mayDrawInIt {
            #expect(
                present.contains(excused),
                """
                \(excused) is excused from following the type scale and is not in the app \
                any more — an exemption nobody can see is one the next file to take that \
                name inherits
                """
            )
        }
    }

    /// Every `.swift` file under a directory, however deeply nested — so a
    /// source added later is covered without anyone remembering to list it.
    /// Paired with the path it sits at relative to that directory, which is
    /// what the list above names them by.
    private func swiftSources(in directory: URL) throws -> [(path: String, url: URL)] {
        let found = try FileManager.default
            .subpathsOfDirectory(atPath: directory.path())
            .filter { $0.hasSuffix(".swift") }
            .map { (path: $0, url: directory.appending(path: $0)) }
        #expect(!found.isEmpty, "found no sources to check at \(directory.path())")
        return found
    }
}
