import SwiftUI
import UIKit

/// One size on the identity's type scale: a face, the size it is set at while
/// Dynamic Type is where it left the factory, which of the system's text
/// styles it grows with, and the tracking the identity draws it with.
///
/// Named by role and never by size. A screen asks for `.rowLabel`, not for
/// "16.5 point regular" — which is what lets the scale be retuned, and what
/// stops the fourth screen inventing a fifth size that is one point off the
/// other four.
///
/// **Everything here answers Dynamic Type.** That is the decision, and it is
/// not a screen's to reopen: the S/M/L/XL control in the app is a *writing*
/// preference — how big somebody wants their own words, the way they pick a
/// pen — and reaches the Entry alone. Every other size in Aujour follows the
/// system's text size, because that is a decision the reader already made for
/// everything they read, and an app that ignored it would be the one on the
/// device they cannot use (`CONTEXT.md`, Device Settings).
///
/// The size is the base and never the last word, so the number on a role is
/// what the reader sees only at the factory setting. What they actually get is
/// that number put through `UIFontMetrics` for the style beside it, which is
/// also what bounds it — a role that grows with `.caption` does not overtake
/// one that grows with `.title2` at any setting on the slider.
struct Lettering: Equatable {
    enum Face: Equatable {
        case system(UIFont.Weight)
        case newsreader(Newsreader.Weight, Newsreader.Slant)
    }

    let face: Face
    /// The size while Dynamic Type is at its factory setting.
    let size: CGFloat
    /// Which of the system's text styles this grows with.
    let style: UIFont.TextStyle
    /// Extra space between letters, in points at the base size. The identity
    /// opens up its small capitals and tightens its titles.
    let tracking: CGFloat

    init(_ face: Face, size: CGFloat, growsWith style: UIFont.TextStyle, tracking: CGFloat = 0) {
        self.face = face
        self.size = size
        self.style = style
        self.tracking = tracking
    }

    // MARK: - Chrome

    /// The name of a screen.
    static let screenTitle = Lettering(.system(.bold), size: 26, growsWith: .title1, tracking: -0.4)

    /// The name of a sheet, or of a section a screen is built out of.
    static let sheetTitle = Lettering(.system(.bold), size: 22, growsWith: .title2, tracking: -0.3)

    /// What a row is called — the left-hand side of every settings row, and
    /// the default size for anything a finger acts on.
    static let rowLabel = Lettering(.system(.regular), size: 16.5, growsWith: .body, tracking: -0.2)

    /// What a row currently says, on its right-hand side.
    static let rowValue = Lettering(.system(.regular), size: 15, growsWith: .subheadline)

    /// The small capitals over a group of rows.
    static let sectionHeader =
        Lettering(.system(.semibold), size: 12.5, growsWith: .caption1, tracking: 0.7)

    /// The sentence under a control that says what it does, and every other
    /// aside set in the system face.
    static let note = Lettering(.system(.regular), size: 12.5, growsWith: .footnote)

    /// The day the app is on, named on the header's date pill.
    ///
    /// Not `screenTitle`, though it is the only thing on screen saying what is
    /// on it: a title that size would not share a 44-point pill with a chip
    /// and a chevron, and the pill is a control before it is a heading. So it
    /// is the row label's size, set in the weight that makes it the one thing
    /// read first.
    static let dayOnScreen =
        Lettering(.system(.semibold), size: 16.5, growsWith: .body, tracking: -0.2)

    /// The lettering on a pill: a chip, a "Today" button, a tag.
    static let chipLabel = Lettering(.system(.medium), size: 13, growsWith: .footnote)

    /// A single letter or figure standing for something — a weekday's initial
    /// over a calendar column, a count beside a heading.
    static let marker = Lettering(.system(.medium), size: 11, growsWith: .caption2, tracking: 0.6)

    // MARK: - Prose

    /// The identity's speaking voice: an empty state, and anything else where
    /// the app addresses the reader in a full sentence rather than labelling
    /// something.
    static let pageVoice = Lettering(.newsreader(.light, .roman), size: 21, growsWith: .title3)

    /// The same voice, quieter and turned aside — "Nothing is saved until you
    /// write."
    static let aside = Lettering(.newsreader(.light, .italic), size: 17, growsWith: .body)

    /// A day's own words, where they are being read rather than written: a
    /// search result, an export, a preview. The Entry's *editor* does not come
    /// here — what the user writes in is their own choice, and it is the one
    /// size on the device the S/M/L/XL control moves.
    static let prose = Lettering(.newsreader(.regular, .roman), size: 17, growsWith: .body)

    /// A heading inside a day.
    static let proseHeading = Lettering(.newsreader(.medium, .roman), size: 24, growsWith: .title2)

    /// Whether this role is set in the identity's prose face — what tells the
    /// two halves of the scale apart without a second list to keep in step.
    var isProse: Bool {
        if case .newsreader = face { return true }
        return false
    }

    /// Every role on the scale, named — so a test that holds *all* of them to
    /// something does not have to be edited each time one is added, which is
    /// the edit that gets forgotten.
    static let everyRole: [(name: String, lettering: Lettering)] = [
        ("screenTitle", screenTitle), ("sheetTitle", sheetTitle), ("rowLabel", rowLabel),
        ("rowValue", rowValue), ("sectionHeader", sectionHeader), ("note", note),
        ("dayOnScreen", dayOnScreen), ("chipLabel", chipLabel), ("marker", marker),
        ("pageVoice", pageVoice), ("aside", aside), ("prose", prose),
        ("proseHeading", proseHeading),
    ]

    /// The font this role comes out as, for the screen it is being drawn on.
    ///
    /// - Parameter traits: whose Dynamic Type setting to scale against. The
    ///   view's own, so that the size is right on the screen it lands on —
    ///   `nil` means whatever is current, which is what SwiftUI has in hand
    ///   while it is evaluating a body.
    func uiFont(compatibleWith traits: UITraitCollection?) -> UIFont {
        UIFontMetrics(forTextStyle: style)
            .scaledFont(for: uiFont(ofSize: size), compatibleWith: traits)
    }

    /// This role's face and weight, at a size somebody else decides — and so
    /// without Dynamic Type, which has already had its say by then.
    ///
    /// The exception the rule above needs, and the only one: something drawn
    /// *inside* an Entry is measured against the line it stands in, because
    /// the Entry is the one thing on the device the S/M/L/XL writing control
    /// moves and a role's own points are not that. What the role still decides
    /// is the face, which is what a caller comes here for
    /// (``DrawnMarkdown/chipLettering(in:)`` is the one).
    func uiFont(ofSize size: CGFloat) -> UIFont {
        switch face {
        case .system(let weight): .systemFont(ofSize: size, weight: weight)
        case .newsreader(let weight, let slant): Newsreader.face(weight, slant, size: size)
        }
    }

    /// This role's tracking at that size — the companion to
    /// ``uiFont(ofSize:)``, and there for the same reason
    /// ``tracking(compatibleWith:)`` is: tracking is not part of a font, and a
    /// role that arrived on screen without it is a role drawn wrong.
    func tracking(atSize size: CGFloat) -> CGFloat {
        guard tracking != 0 else { return 0 }
        return tracking * size / self.size
    }

    /// How far apart the letters go once Dynamic Type has had the size — so
    /// that tracking set for a 12-point label does not stay a 12-point gap
    /// when the label is 30 points.
    func tracking(compatibleWith traits: UITraitCollection?) -> CGFloat {
        tracking(atSize: uiFont(compatibleWith: traits).pointSize)
    }
}

extension View {
    /// Sets this view's text on the identity's scale.
    ///
    /// A modifier rather than a `Font` a caller passes to `.font()`, because
    /// tracking is not part of a font and a role that lost its tracking on the
    /// way to the screen would be a role drawn wrong on the screens that
    /// needed it most — the small capitals over a section are tracking as much
    /// as they are size.
    ///
    /// The size is taken from `dynamicTypeSize` in the environment rather than
    /// from whatever `UITraitCollection` happens to be current, and that is
    /// load-bearing twice over. It is the size SwiftUI is actually laying this
    /// view out at, which is not the same thing in a preview or under a
    /// `.dynamicTypeSize()` override; and *reading* it is what tells SwiftUI
    /// this view has to be evaluated again when the reader moves the system
    /// slider. A modifier that declared the dependency and then did not use
    /// the value would be right on launch and stale from then on.
    func lettering(_ lettering: Lettering) -> some View {
        modifier(LetteringModifier(lettering: lettering))
    }
}

private struct LetteringModifier: ViewModifier {
    let lettering: Lettering

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.contentSize)
        return
            content
            .font(Font(lettering.uiFont(compatibleWith: traits)))
            .tracking(lettering.tracking(compatibleWith: traits))
    }
}

extension DynamicTypeSize {
    /// The same setting, in the vocabulary `UIFontMetrics` speaks.
    ///
    /// A mapping and not a cast: SwiftUI and UIKit name the twelve steps of
    /// one slider differently, and there is no initializer either way. Written
    /// out case by case, so that a step SwiftUI adds shows up as a warning
    /// here — `DynamicTypeSize` can grow, which is why the `@unknown default`
    /// has to be there at all, and the factory setting is the least wrong
    /// thing to answer a step this build has never heard of.
    var contentSize: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
