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
    /// What a user is offered this colour as.
    var name: String {
        switch self {
        case .ink: "Ink"
        case .plum: "Plum"
        case .rose: "Rose"
        case .amber: "Amber"
        case .moss: "Moss"
        case .sea: "Sea"
        }
    }

    /// The colour itself: one shade for a light page, a lighter one for a dark
    /// page. Both are chosen to carry a checkbox and a widget's lettering at
    /// small sizes, which is the job the accent actually has — a colour that
    /// looks handsome in a swatch and vanishes in a tick box is the wrong one.
    ///
    /// Looked up rather than built, so that the same accent asked for twice is
    /// the same colour object. The editor decides whether to redraw a day by
    /// comparing the colour it is drawing in against the one it should be, and
    /// two freshly built dynamic colours never compare equal — every keystroke
    /// would restyle thousands of words.
    var uiColor: UIColor {
        switch self {
        case .ink: Self.ink
        case .plum: Self.plum
        case .rose: Self.rose
        case .amber: Self.amber
        case .moss: Self.moss
        case .sea: Self.sea
        }
    }

    /// The same colour, for the SwiftUI half of the app.
    var color: Color { Color(uiColor) }

    private static let ink = dynamic(light: (0.15, 0.27, 0.55), dark: (0.47, 0.63, 0.96))
    private static let plum = dynamic(light: (0.45, 0.19, 0.51), dark: (0.78, 0.55, 0.87))
    private static let rose = dynamic(light: (0.67, 0.15, 0.32), dark: (0.96, 0.51, 0.61))
    private static let amber = dynamic(light: (0.61, 0.39, 0.04), dark: (0.94, 0.72, 0.29))
    private static let moss = dynamic(light: (0.21, 0.42, 0.22), dark: (0.55, 0.77, 0.50))
    private static let sea = dynamic(light: (0.05, 0.39, 0.46), dark: (0.36, 0.77, 0.81))

    private static func dynamic(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> UIColor {
        UIColor { traits in
            let (red, green, blue) = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: red, green: green, blue: blue, alpha: 1)
        }
    }
}

extension EditorFont {
    /// The typeface this choice is, at the size it is, moved by whatever
    /// Dynamic Type is set to.
    ///
    /// The chosen size is the *base* and not the last word: somebody who has
    /// turned the system's text up has turned up everything they read, and an
    /// editor that ignored that would be the one app on the device they
    /// cannot read. So the number in Settings is what the editor draws at
    /// while Dynamic Type is where it left the factory, and it moves with the
    /// system from there.
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
            .systemFont(ofSize: size)
        case .serif:
            // New York, by way of the system font's own serif design: the same
            // metrics and the same language coverage as the face beside it,
            // rather than a named font that may not be on the device.
            UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
                .map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
        case .monospaced:
            .monospacedSystemFont(ofSize: size, weight: .regular)
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
