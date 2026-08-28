import AujourCore
import SwiftUI
import UIKit

// What the device's choices about how Aujour looks come out as once there is a
// screen to draw them on: a colour for the accent, a typeface for the editor.
//
// Core says *which* accent and *which* family, because that is what has to be
// stored and to survive a relaunch. It stops there deliberately — a colour is a
// different thing in light and in dark, and a point size is a different number
// once Dynamic Type has had it, and neither is knowable without a trait
// collection to ask.

extension Theme {
    /// What a user is offered this appearance as.
    ///
    /// "Auto" and not "System": the choice is whether Aujour decides or the
    /// device does, and "system" is the word for the thing deciding rather
    /// than for what the user gets.
    var name: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The order the three are offered in: the two that are instructions,
    /// and then the one that hands the decision back.
    ///
    /// Written out rather than taken off `allCases`, because the order a
    /// control reads in is the screen's business and the order an enum is
    /// declared in is the model's — `.system` is first there because it is
    /// the default, and first on a segmented control it would be the odd one
    /// between two that pair. A test holds this to every case there is, so a
    /// fourth theme cannot arrive with no way to pick it.
    static let asOffered: [Theme] = [.light, .dark, .system]
}

extension EditorFont.Family {
    /// What a user is offered this typeface as.
    var name: String {
        switch self {
        case .system: "Sans"
        case .serif: "Serif"
        case .monospaced: "Mono"
        }
    }
}

extension Accent {
    /// What a user is offered this colour as — the identity's own names.
    var name: String {
        switch self {
        case .driftwood: "Driftwood"
        case .terracotta: "Terracotta"
        case .clay: "Clay"
        case .ochre: "Ochre"
        case .olive: "Olive"
        case .sage: "Sage"
        case .harbour: "Harbour"
        case .plum: "Plum"
        case .graphite: "Graphite"
        }
    }

    /// The colour itself: one shade for a light page, a lighter one for a dark
    /// page.
    ///
    /// **What a shape is drawn in, and what a word is drawn in on bare paper.**
    /// The identity's values, raised where they had to be. Composited as the
    /// design file specifies them, Terracotta reads at 3.57:1 and Ochre at
    /// 3.70:1 as text on the sheet, and an accent is not decoration here — it
    /// carries a widget's lettering, a settings row's value and the way back
    /// out. So every one of these clears 4.5:1 on every ground the app can
    /// draw it on, `--bg` included, which is the darkest of the light grounds
    /// and the one the calendar's today-marker sits on (ADR 0006).
    ///
    /// Looked up rather than built, so that the same accent asked for twice is
    /// the same colour object. The editor decides whether to redraw a day by
    /// comparing the colour it is drawing in against the one it should be, and
    /// two freshly built dynamic colours never compare equal — every keystroke
    /// would restyle thousands of words.
    var uiColor: UIColor {
        switch self {
        case .driftwood: Self.driftwood
        case .terracotta: Self.terracotta
        case .clay: Self.clay
        case .ochre: Self.ochre
        case .olive: Self.olive
        case .sage: Self.sage
        case .harbour: Self.harbour
        case .plum: Self.plum
        case .graphite: Self.graphite
        }
    }

    /// The shade a word takes when it is written **on a wash of this accent** —
    /// a "Today" pill, a place chip, a highlighted run in a search result.
    ///
    /// A second shade and not a reuse of the first, because a colour written on
    /// a wash of itself loses about a point of contrast, and every accent lands
    /// between 3.6:1 and 4.4:1 that way — under the floor, in the exact places
    /// the identity likes tinted pills most. So this is the accent taken a
    /// step darker in light and a step lighter in dark — as little as 3% and
    /// as much as 23%, whatever each one needed — until it clears 4.5:1 on its
    /// own wash as well as on bare paper. The design file names
    /// the same pair (`--accent` and `--accent-ink`) and only its JavaScript
    /// collapses them.
    ///
    /// The rule downstream is one sentence, so that it cannot be got subtly
    /// wrong: **`inkColor` is for accent-coloured words, `uiColor` is for
    /// accent-coloured shapes.** Both clear the floor on bare paper, so the
    /// rule costs nothing where it does not matter.
    var inkColor: UIColor {
        switch self {
        case .driftwood: Self.driftwoodInk
        case .terracotta: Self.terracottaInk
        case .clay: Self.clayInk
        case .ochre: Self.ochreInk
        case .olive: Self.oliveInk
        case .sage: Self.sageInk
        case .harbour: Self.harbourInk
        case .plum: Self.plumInk
        case .graphite: Self.graphiteInk
        }
    }

    /// The accent thinned to a wash: the fill under a chip, a pill, a selected
    /// day that is today rather than the one being read.
    ///
    /// The accent at an alpha rather than nine more opaque colours, so it is
    /// right over paper, over a card and over a sheet without three sets to
    /// keep in step. A hair stronger in dark, where a wash of this weight over
    /// near-black would otherwise not be there at all.
    var softColor: UIColor { Self.softWashes[self] ?? uiColor }

    /// The same wash, at the weight the identity draws a quote bar and a
    /// selected edge in — strong enough to be a line rather than a tint.
    var softerColor: UIColor { Self.softerWashes[self] ?? uiColor }

    /// The same colours, for the SwiftUI half of the app.
    var color: Color { Color(uiColor) }
    var ink: Color { Color(inkColor) }
    var soft: Color { Color(softColor) }
    var softer: Color { Color(softerColor) }

    private static let driftwood = dynamic(light: 0x7B6A52, dark: 0xA79A80)
    // Darkened from the identity's #B8724A, which reads at 3.57:1.
    private static let terracotta = dynamic(light: 0x9B603E, dark: 0xD08E63)
    private static let clay = dynamic(light: 0xA8563C, dark: 0xC87A5C)
    // Darkened from the identity's #9C7B4D, which reads at 3.70:1.
    private static let ochre = dynamic(light: 0x866943, dark: 0xC2A06A)
    private static let olive = dynamic(light: 0x687250, dark: 0x9AA478)
    private static let sage = dynamic(light: 0x5B7466, dark: 0x8AA79A)
    private static let harbour = dynamic(light: 0x56708C, dark: 0x88A2BC)
    private static let plum = dynamic(light: 0x7B5A72, dark: 0xA9849F)
    private static let graphite = dynamic(light: 0x6B6660, dark: 0x9C958D)

    private static let driftwoodInk = dynamic(light: 0x6F5F4A, dark: 0xB0A48C)
    private static let terracottaInk = dynamic(light: 0x8A5537, dark: 0xD49972)
    private static let clayInk = dynamic(light: 0x964D36, dark: 0xD2937A)
    private static let ochreInk = dynamic(light: 0x775D3C, dark: 0xC4A36E)
    private static let oliveInk = dynamic(light: 0x5D6547, dark: 0xA1AB82)
    private static let sageInk = dynamic(light: 0x51675B, dark: 0x91ADA0)
    private static let harbourInk = dynamic(light: 0x4D647E, dark: 0x90A9C1)
    private static let plumInk = dynamic(light: 0x78576F, dark: 0xB89AB0)
    private static let graphiteInk = dynamic(light: 0x65615B, dark: 0xA9A39C)

    /// Built once per accent rather than on each call, for the same reason the
    /// accents themselves are looked up: a wash handed to the editor twice has
    /// to be the same object, or every keystroke restyles the day.
    ///
    /// Built off `allCases` rather than written out, so an accent added to the
    /// set arrives with its washes instead of quietly having none.
    private static let softWashes = washes(light: 0.15, dark: 0.18)
    private static let softerWashes = washes(light: 0.35, dark: 0.35)

    private static func dynamic(light: Int, dark: Int) -> UIColor {
        UIColor { traits in
            UIColor(identity: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    private static func washes(light: CGFloat, dark: CGFloat) -> [Accent: UIColor] {
        Dictionary(
            uniqueKeysWithValues: Accent.allCases.map { accent in
                (
                    accent,
                    UIColor { traits in
                        accent.uiColor.resolvedColor(with: traits)
                            .withAlphaComponent(traits.userInterfaceStyle == .dark ? dark : light)
                    }
                )
            }
        )
    }
}

extension EditorFont {
    /// The typeface this choice is, at the size that step is worth, moved by
    /// whatever Dynamic Type is set to.
    ///
    /// The chosen step is the *base* and not the last word: somebody who has
    /// turned the system's text up has turned up everything they read, and an
    /// editor that ignored that would be the one app on the device they
    /// cannot read. So the step is what the editor draws at while Dynamic Type
    /// is where it left the factory, and it moves with the system from there.
    ///
    /// - Parameter traits: whose Dynamic Type setting to scale against — the
    ///   text view's, so that the size is right on the screen it is drawn on.
    func uiFont(compatibleWith traits: UITraitCollection?) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: typeface, compatibleWith: traits)
    }

    /// The face at the chosen size, before Dynamic Type is applied to it.
    private var typeface: UIFont {
        switch family {
        case .system:
            .systemFont(ofSize: size.points)
        case .serif:
            // New York, by way of the system font's own serif design: the same
            // metrics and the same language coverage as the face beside it,
            // rather than a named font that may not be on the device.
            UIFont.systemFont(ofSize: size.points).fontDescriptor.withDesign(.serif)
                .map { UIFont(descriptor: $0, size: size.points) } ?? .systemFont(ofSize: size.points)
        case .monospaced:
            .monospacedSystemFont(ofSize: size.points, weight: .regular)
        }
    }
}

extension EditorFont.Size {
    /// What a step is worth in points, before Dynamic Type moves it.
    ///
    /// Whole points two apart, around the system's own body size at M. Whole,
    /// because `UIFontMetrics` rounds a half point away and a step nobody can
    /// see is a step that should not be on the control; two apart, because
    /// four steps a point apart is a control that does nothing four times.
    ///
    /// The identity draws its prose over 15.5–19.5, which is a range in a web
    /// mock rather than a set of iOS point sizes; this is that range read as
    /// points and opened up enough to be worth tapping. What the user picks is
    /// a step, and the number under it is this layer's to retune without
    /// anybody's choice changing.
    var points: CGFloat {
        switch self {
        case .small: 15
        case .medium: 17
        case .large: 19
        case .extraLarge: 21
        }
    }

    /// What a user is offered this step as.
    var name: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .extraLarge: "XL"
        }
    }
}

/// How the editor is to draw: the typeface the user chose, and the one colour
/// the app spends on itself.
///
/// One value rather than two properties, because it travels as one — from the
/// device's settings, down through whichever day is on screen, to the text
/// view. Equatable so the editor can tell at a glance that a keystroke changed
/// nothing about how the words should look.
struct EditorLook: Equatable {
    var font: EditorFont
    var accent: Accent

    /// What the editor draws in before anybody has chosen anything — the
    /// device's own defaults, asked for rather than restated, so there is one
    /// place a default lives (`DeviceSettings`).
    static let `default` = EditorLook(
        font: DeviceSettings.default.editorFont,
        accent: DeviceSettings.default.accent
    )

    /// Everything the editor needs to draw markdown in, for the screen it is
    /// being drawn on.
    func styling(compatibleWith traits: UITraitCollection?) -> MarkdownStyling {
        MarkdownStyling(
            body: font.uiFont(compatibleWith: traits),
            link: accent.uiColor,
            box: accent.uiColor
        )
    }
}

extension EnvironmentValues {
    /// How the editor is to draw, put where the editor can reach it.
    ///
    /// Through the environment rather than handed down, because between the
    /// device's settings and the text view are the day on screen, the calendar
    /// that pushed it and the search results that pushed it — none of which
    /// have anything to say about typefaces, and all of which would have to
    /// carry one.
    ///
    /// It has a default, so a preview and a test of something else get the
    /// same editor everybody starts with rather than a crash.
    var editorLook: EditorLook {
        get { self[EditorLookKey.self] }
        set { self[EditorLookKey.self] = newValue }
    }
}

private struct EditorLookKey: EnvironmentKey {
    static let defaultValue = EditorLook.default
}
