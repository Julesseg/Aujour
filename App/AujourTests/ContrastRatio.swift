import UIKit

// What ADR 0006's floor is measured with. Not app code: nothing Aujour draws
// ever asks how legible it is — the floor is a property of the palette, so it
// is checked where the palette is checked and nowhere else.

/// A colour as it actually lands on a screen: resolved for one appearance,
/// and composited onto whatever is behind it if it is not opaque.
///
/// Composited and not just read, because most of the identity's inks are the
/// same near-black at different alphas. `--ink-3` is 2.28:1 on paper and
/// 4.10:1 on a dark card, and only one of those numbers is about a token —
/// the other is about a token *and the ground it was drawn on*. So a
/// measurement here always names a ground.
struct Landed {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    /// - Parameters:
    ///   - colour: the token.
    ///   - style: light or dark — which of the two values the token is.
    ///   - ground: what is behind it. Opaque, and resolved for the same
    ///     appearance, or the answer is about a screen nobody is looking at.
    init(_ colour: UIColor, in style: UIUserInterfaceStyle, over ground: UIColor? = nil) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let (front, alpha) = colour.resolvedColor(with: traits).components
        guard alpha < 1, let ground else {
            (red, green, blue) = front
            return
        }
        let (behind, _) = ground.resolvedColor(with: traits).components
        red = alpha * front.red + (1 - alpha) * behind.red
        green = alpha * front.green + (1 - alpha) * behind.green
        blue = alpha * front.blue + (1 - alpha) * behind.blue
    }

    /// WCAG 2 relative luminance.
    private var luminance: CGFloat {
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// How far apart these two are, as WCAG counts it: 1 for two colours
    /// nobody can tell apart, 21 for black on white.
    func contrast(against other: Landed) -> CGFloat {
        let (lighter, darker) = (
            max(luminance, other.luminance), min(luminance, other.luminance)
        )
        return (lighter + 0.05) / (darker + 0.05)
    }
}

extension UIColor {
    fileprivate var components: (rgb: (red: CGFloat, green: CGFloat, blue: CGFloat), alpha: CGFloat)
    {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return ((red, green, blue), alpha)
    }
}

extension UIColor {
    /// The colour this is in one appearance, as `#RRGGBB` — so a test can say
    /// which value it expected in the identity's own notation.
    ///
    /// Opaque tokens only. Half the palette is one near-black at a dozen
    /// alphas, and for those this says `#241F1B` a dozen times over.
    func hex(in style: UIUserInterfaceStyle) -> String {
        let landed = Landed(self, in: style)
        return String(
            format: "#%02X%02X%02X",
            Int((landed.red * 255).rounded()),
            Int((landed.green * 255).rounded()),
            Int((landed.blue * 255).rounded())
        )
    }

    /// Everything about what this token comes out as in one appearance,
    /// alpha included — which is what tells two tokens apart when they are the
    /// same white at two very different weights.
    func resolved(in style: UIUserInterfaceStyle) -> String {
        var alpha: CGFloat = 0
        resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            .getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return hex(in: style) + String(format: "@%.3f", alpha)
    }
}
