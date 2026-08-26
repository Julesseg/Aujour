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
    /// The identity's values, raised where they had to be. Composited as the
    /// design file specifies them, Terracotta reads at 3.57:1 and Ochre at
    /// 3.70:1 as text on the sheet, and an accent is not decoration here — it
    /// carries a widget's lettering, a settings row's value and the way back
    /// out. So every one of these clears 4.5:1 against the ground it is drawn
    /// on, which cost Terracotta and Ochre a visible amount of their warmth
    /// and Olive and Sage a hair of theirs (ADR 0006).
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

    /// The same colour, for the SwiftUI half of the app.
    var color: Color { Color(uiColor) }

    private static let driftwood = dynamic(light: 0x7B6A52, dark: 0xA79A80)
    // Darkened from the identity's #B8724A, which reads at 3.57:1.
    private static let terracotta = dynamic(light: 0xA06340, dark: 0xD08E63)
    private static let clay = dynamic(light: 0xA8563C, dark: 0xC87A5C)
    // Darkened from the identity's #9C7B4D, which reads at 3.70:1.
    private static let ochre = dynamic(light: 0x8B6D45, dark: 0xC2A06A)
    private static let olive = dynamic(light: 0x6C7753, dark: 0x9AA478)
    private static let sage = dynamic(light: 0x5E786A, dark: 0x8AA79A)
    private static let harbour = dynamic(light: 0x56708C, dark: 0x88A2BC)
    private static let plum = dynamic(light: 0x7B5A72, dark: 0xA9849F)
    private static let graphite = dynamic(light: 0x6B6660, dark: 0x9C958D)

    private static func dynamic(light: Int, dark: Int) -> UIColor {
        UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }
}

extension UIColor {
    /// A colour written the way the identity writes one: `0xRRGGBB`, so a
    /// value here can be read straight off the design file.
    fileprivate convenience init(rgb: Int) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
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
