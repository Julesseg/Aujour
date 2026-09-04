import SwiftUI
import UIKit

/// Every colour Aujour draws with that is not the accent: the paper, the ink
/// on it, the rules between things, and the glass the chrome floats on.
///
/// One place, so that "what colour is this" has an answer rather than nine
/// answers scattered across the screens that needed one. A screen names a
/// role — `Palette.card`, `Palette.inkFaint` — and never a value, which is
/// what lets the identity be re-cut without a hunt through the app for hex
/// codes somebody typed in once.
///
/// Two decisions are baked in here and are not a screen's to reopen.
///
/// The first is that every token is a *dynamic* colour, resolved against the
/// screen it lands on, and never a pair a caller picks between. A screen that
/// asked which appearance was in force in order to choose a colour would be a
/// screen that gets it wrong in a sheet, in a widget, and in the half of a
/// split view whose override differs from the window's — the trait collection
/// already knows, and it knows in places a view does not.
///
/// The second is the contrast floor (ADR 0006). The identity's own values
/// are softer than these; where a token carries a sentence it is raised until
/// the sentence clears 4.5:1 on every ground it can be drawn on, and where it
/// carries a marker it clears 3:1. The design file is prettier than this and
/// the difference is deliberate — the tests in `IdentityTests` are the floor,
/// not the design file.
///
/// Looked up rather than built, for the reason `Accent.uiColor` is: two
/// freshly built dynamic colours never compare equal, and the editor decides
/// whether to restyle a day's worth of words by comparing the colours it is
/// drawing in against the ones it should be.
enum Palette {
    // MARK: - The paper

    /// The page itself — what a screen with nothing on it is.
    static let background = dynamic(light: 0xF6F2EC, dark: 0x16130F)

    /// A raised surface on the page: a settings group, a specimen, anything
    /// that is a *thing* on the paper rather than the paper.
    ///
    /// Lifted on 2026-09-04, when the settings became grouped `Form`s and put
    /// the token to the one use it had never really been asked to do: a card
    /// on a *sheet* rather than on the page. The sheet's ground is a hair off
    /// the page's own, so what read as clearly raised over `background` read
    /// as barely there over `sheet` — four points of separation in light and
    /// five in dark.
    ///
    /// The dark step is where the room was: fourteen points clear of the sheet
    /// now against five before. It stops at `0x292520` and the ceiling is not
    /// aesthetic — a card is a **ground**, so every accent's ink is measured
    /// against a wash of that accent over it, and graphite's is the tightest
    /// of the nine. At this value it reads 4.57:1; one step lighter
    /// (`0x2B2721`) it reads 4.46 and is under ADR 0006's floor. Anything
    /// lighter than this has to be bought from the accents.
    ///
    /// In light the token was already three points off white, so what it
    /// gains there is small by arithmetic rather than by choice — enough to
    /// tell the card from the paper, not enough to make it the cold white a
    /// grouped list would have drawn on its own.
    static let card = dynamic(light: 0xFFFEFC, dark: 0x292520)

    /// The ground of a sheet, which is a hair off the page's own so that a
    /// sheet over a screen reads as being in front of it.
    static let sheet = dynamic(light: 0xFBF8F2, dark: 0x1B1712)

    // MARK: - The ink, and its two muted steps

    /// What a sentence is written in.
    static let ink = dynamic(light: 0x241F1B, dark: 0xF2EDE5)

    /// The quieter of the two steps down: a second line under a first, a
    /// caption, an empty state's sentence. Still a sentence, so still held to
    /// 4.5:1 — the identity draws this at `.62` in light, which measures
    /// 4.45:1 on paper and misses the floor by a hair.
    static let inkMuted =
        dynamic(light: 0x241F1B, dark: 0xF2EDE5, lightAlpha: 0.64, darkAlpha: 0.60)

    /// The faintest step: markers, chevrons, the small capitals over a
    /// section, a field's placeholder. **Never a sentence.**
    ///
    /// This is the one token in the palette that is deliberately below the
    /// sentence floor, and the constraint runs the other way — raised to
    /// 4.5:1 it would sit on top of `inkMuted` and the identity would have
    /// lost a step it uses everywhere. At the identity's `.52` light and
    /// `.46` dark it measures 3.31:1 and 3.93:1 on the worst ground it can
    /// land on, which is the marker floor and not the sentence one. So a
    /// sentence takes `inkMuted`, however quiet the design wants it to look.
    static let inkFaint =
        dynamic(light: 0x241F1B, dark: 0xF2EDE5, lightAlpha: 0.52, darkAlpha: 0.46)

    // MARK: - Rules and fields

    /// A hairline between two rows, or around a card. Not held to the floor:
    /// a rule is not a marker and carries nothing — it is the absence of a
    /// gap, and a reader who cannot see it loses nothing but a suggestion.
    static let rule = dynamic(light: 0x241F1B, dark: 0xF2EDE5, lightAlpha: 0.10, darkAlpha: 0.12)

    /// The tint under something a finger goes into: a search field, a
    /// segmented control's trough, a day the journal already has an entry for.
    static let field = dynamic(light: 0x241F1B, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.08)

    /// The same, one step more definite — a track a thumb slides along, where
    /// the trough has to be visible rather than merely felt.
    static let fieldStrong =
        dynamic(light: 0x241F1B, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.14)

    // MARK: - Glass

    /// The fill of something floating over content: a banner, a toolbar.
    /// Translucent by design — what is behind it should be legible as *being*
    /// behind it.
    ///
    /// An *account* of glass and not the thing itself. Where a pane really
    /// floats over a page of somebody's writing — the date pill — the system's
    /// own `glassEffect` is what draws it: it refracts what scrolls under it
    /// and answers Reduce Transparency without being asked, neither of which a
    /// colour can do. What this is for is everything a colour still has to
    /// answer, chiefly `glassSolid` below, which is the ground a contrast
    /// floor is measured against.
    static let glass = dynamic(light: 0xFFFCF7, dark: 0x3C362F, lightAlpha: 0.62, darkAlpha: 0.55)

    /// The half-point border that gives a pane of glass an edge. Without it
    /// translucency reads as a smudge rather than as a layer.
    static let glassRing =
        dynamic(light: 0x241F1B, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.14)

    /// The lit top edge of a pane, which is what makes it read as glass and
    /// not as a rectangle of paint.
    static let glassHighlight =
        dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.70, darkAlpha: 0.16)

    // MARK: - On the accent

    /// What a mark is when it is drawn *on* a fill of the accent rather than
    /// in it: the pressed key on the accessory row.
    ///
    /// The paper of the appearance the accent was tuned against, which is why
    /// it is not `card` or `background` under another name — it is near-white
    /// in light, where the accents are dark enough to carry it, and near-black
    /// in dark, where they are light. Every one of the nine clears 4.5:1
    /// against it in both appearances (`AccentContrastTests`), so a mark here
    /// is held to the sentence floor even though ADR 0006 would settle for the
    /// marker one.
    ///
    /// Not an ink: it lands on the accent and never on paper, and on paper it
    /// would be invisible. The floor tests hold the inks to the grounds and
    /// hold this to the accents, which is the difference said in tests.
    static let onAccent = dynamic(light: 0xFFFCF7, dark: 0x16130F)

    /// What a pane of glass is when it cannot be one: the opaque colour it
    /// averages to.
    ///
    /// There for Reduce Transparency, and for the tests — a floor measured
    /// against a translucent ground is a floor measured against whatever
    /// happened to be scrolling underneath, so this is the ground the tests
    /// hold glass-borne ink to.
    static let glassSolid = dynamic(light: 0xF6F2EC, dark: 0x2A251F)

    // MARK: - When something is wrong

    /// The one colour in the identity that is not paper, ink or the accent:
    /// what a sentence is written in when it is telling the reader something
    /// has gone wrong and will stay wrong until they do something about it.
    ///
    /// Not `.red`. The system's is `#FF3B30` on paper, which measures 3.18:1
    /// against `background` — a sentence under the floor, on the two screens
    /// where the sentence is the whole point (ADR 0006). This is the
    /// identity's own: a brick red in the same earth family as the accents,
    /// dark enough in light and light enough in dark to clear 4.5:1 on every
    /// ground it can land on.
    ///
    /// Rare on purpose. Nothing routine is drawn in it — a partial migration
    /// is reported in the accent, and a folder that could not be read is a
    /// notice rather than an alarm. What this is for is the state the app
    /// cannot get itself out of: notifications turned off under a reminder
    /// somebody has just asked for.
    static let alarm = dynamic(light: 0xA32A1A, dark: 0xF08578)

    // MARK: - The same colours, for the SwiftUI half of the app

    // Wrapped once each rather than on every read, for the reason the tokens
    // above are looked up rather than built: a view that is handed a freshly
    // made colour every time it is evaluated is a view SwiftUI cannot tell has
    // not changed.

    static let backgroundColor = Color(background)
    static let cardColor = Color(card)
    static let sheetColor = Color(sheet)
    static let inkColor = Color(ink)
    static let inkMutedColor = Color(inkMuted)
    static let inkFaintColor = Color(inkFaint)
    static let ruleColor = Color(rule)
    static let fieldColor = Color(field)
    static let fieldStrongColor = Color(fieldStrong)
    static let glassColor = Color(glass)
    static let glassRingColor = Color(glassRing)
    static let glassHighlightColor = Color(glassHighlight)
    static let glassSolidColor = Color(glassSolid)
    static let onAccentColor = Color(onAccent)
    static let alarmColor = Color(alarm)

    /// Every token, named — so a test that has to hold *all* of them to
    /// something does not have to be edited each time one is added, which is
    /// the edit that gets forgotten.
    static let everyToken: [(name: String, colour: UIColor)] = [
        ("background", background), ("card", card), ("sheet", sheet),
        ("ink", ink), ("inkMuted", inkMuted), ("inkFaint", inkFaint),
        ("rule", rule), ("field", field), ("fieldStrong", fieldStrong),
        ("glass", glass), ("glassRing", glassRing), ("glassHighlight", glassHighlight),
        ("glassSolid", glassSolid), ("onAccent", onAccent), ("alarm", alarm),
    ]

    private static func dynamic(
        light: Int,
        dark: Int,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(identity: dark).withAlphaComponent(darkAlpha)
                : UIColor(identity: light).withAlphaComponent(lightAlpha)
        }
    }
}

extension UIColor {
    /// A colour written the way the identity writes one: `0xRRGGBB`, so a
    /// value here can be read straight off the design file and compared with
    /// it without arithmetic.
    convenience init(identity rgb: Int) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
