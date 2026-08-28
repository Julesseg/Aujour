import SwiftUI
import UIKit

/// How round a corner is, by what it is a corner of.
///
/// Four numbers and not the dozen the design file draws, deliberately. The
/// mock rounds a banner at 20, a settings group at 18 and a specimen at 16,
/// which is three numbers for one idea — nobody can see two points of radius
/// at that size, and a set with three near-identical members is a set every
/// screen has to guess its way into. Collapsing them is the token layer doing
/// its job: what a screen has to know is *what kind of thing it is drawing*,
/// and the number under that is this file's to retune.
///
/// A pill has no entry: it is `Capsule()`, which stays a pill at every size
/// the type scale can grow a label to. The design's `border-radius: 99px` is
/// the same idea written in a language that has no capsule.
enum Rounding {
    /// A chip, a tick box, a highlighted run of a search result — something
    /// small enough that a large radius would eat it.
    static let chip: CGFloat = 6

    /// Something a finger goes into or onto: a field, a segmented trough, a
    /// photo tile.
    static let control: CGFloat = 12

    /// A surface on the page — a settings group, a specimen, a banner.
    static let card: CGFloat = 18

    /// The top corners of a sheet, which are much rounder than anything on
    /// the page because they are the one corner cut against the device's own.
    static let sheet: CGFloat = 38
}

/// How much room to leave, by what the gap is between.
///
/// Four steps on a rough doubling, which is enough to lay out a screen and few
/// enough that a reader can see which two things belong together. The identity
/// draws gaps at 2, 3, 4, 5, 6, 8, 9, 11, 12, 14, 16, 18 and 20 points; most
/// of those differences are a mock being drawn by hand rather than a decision
/// anybody made, and a screen that had to pick between 11 and 12 would be a
/// screen picking at random.
enum Spacing {
    /// Between a thing and its own label — a swatch and its tick, a row's
    /// icon and its words.
    static let tight: CGFloat = 4

    /// Between two things that are one thing: the rows inside a group.
    static let close: CGFloat = 8

    /// The inside of a card, and the gap between a control and the sentence
    /// underneath it explaining it.
    static let comfortable: CGFloat = 12

    /// Between two sections of a screen, and around the edge of one.
    static let apart: CGFloat = 20
}

/// What lifts a surface off the one behind it.
///
/// Shadows and not borders, and layered rather than single, because a paper
/// identity has no other way to say "in front of": one tight shadow for the
/// contact edge and one wide soft one for the lift, which is what stops a
/// card reading as a sticker.
///
/// A value rather than a modifier per elevation, so that "which lift is this"
/// is a thing a view can be handed, compared and stored.
struct Elevation: Equatable {
    /// One shadow. Several of these make an elevation.
    struct Layer: Equatable {
        let opacity: CGFloat
        let radius: CGFloat
        let y: CGFloat
    }

    let layers: [Layer]

    /// A control resting on the surface it is part of — a slider's thumb, a
    /// segmented control's selected segment. Barely there, and the identity
    /// would look wrong without it.
    static let resting = Elevation(layers: [Layer(opacity: 0.25, radius: 1.5, y: 1)])

    /// A surface floating over content that scrolls under it: a banner, a
    /// toolbar. Not the date pill, which is drawn in the system's own glass
    /// and lifts itself.
    static let floating = Elevation(
        layers: [
            Layer(opacity: 0.05, radius: 1, y: 1),
            Layer(opacity: 0.07, radius: 6, y: 4),
        ]
    )

    /// A sheet over the whole screen. Cast upward, because a sheet comes from
    /// the bottom edge and the light in this identity does not.
    static let sheet = Elevation(layers: [Layer(opacity: 0.18, radius: 25, y: -18)])
}

extension Elevation {
    /// The colour a lift is cast in: the identity's own near-black, and the
    /// *same* near-black in both appearances — a shadow is an absence of light,
    /// and one that lightened in dark mode would be a glow.
    static let shadowInk = UIColor(identity: 0x241F1B)

    /// Lifts a UIKit view off what is behind it, as sublayers of its own.
    ///
    /// Sublayers because a `CALayer` has one shadow and an elevation here has
    /// two — the tight contact edge and the wide soft lift, which is the pair
    /// that stops a surface reading as a sticker. One layer each, and each one
    /// given the outline to cast: a layer with nothing drawn in it casts
    /// nothing at all unless it is handed a `shadowPath`.
    ///
    /// So the shapes are the caller's to set, and to set again every time the
    /// view is laid out — which is why the layers are handed back rather than
    /// added and forgotten.
    @discardableResult
    func castOn(_ view: UIView) -> [CALayer] {
        layers.map { layer in
            let shadow = CALayer()
            shadow.shadowColor = Elevation.shadowInk.cgColor
            shadow.shadowOpacity = Float(layer.opacity)
            shadow.shadowRadius = layer.radius
            shadow.shadowOffset = CGSize(width: 0, height: layer.y)
            view.layer.insertSublayer(shadow, at: 0)
            return shadow
        }
    }

    /// Points those shadows at the shape being lifted, and keeps them outside
    /// it.
    ///
    /// Outside it, because Core Animation lays a shadow down under the whole
    /// of its path rather than only around it. Under something opaque that
    /// never shows — the surface covers its own shadow. Under a pane of glass
    /// it is a bruise: the pane samples what is behind it, and what is behind
    /// it is now every layer's worth of near-black. So each shadow is masked
    /// to everything it can reach *except* the shape itself.
    static func shape(_ shadows: [CALayer], like outline: UIBezierPath, in bounds: CGRect) {
        for shadow in shadows {
            shadow.frame = bounds
            shadow.shadowPath = outline.cgPath

            // As far as this one can reach: its blur, plus however far it was
            // pushed, plus a point so the edge is not the mask's own.
            let reach =
                shadow.shadowRadius * 2 + abs(shadow.shadowOffset.height) + 1
            let canvas = bounds.insetBy(dx: -reach, dy: -reach)

            // The mask is drawn in its own corner-origin space, so the hole
            // moves with it.
            let hole = UIBezierPath(rect: CGRect(origin: .zero, size: canvas.size))
            let shape = UIBezierPath(cgPath: outline.cgPath)
            shape.apply(CGAffineTransform(translationX: reach, y: reach))
            hole.append(shape)
            hole.usesEvenOddFillRule = true

            let mask = CAShapeLayer()
            mask.frame = canvas
            mask.path = hole.cgPath
            mask.fillRule = .evenOdd
            shadow.mask = mask
        }
    }
}

extension View {
    /// Lifts this view off what is behind it.
    ///
    /// The shadow is cast in the identity's own near-black rather than in
    /// `.black`, and in the *same* near-black in both appearances: a shadow is
    /// an absence of light, and one that lightened in dark mode would be a
    /// glow.
    func elevated(_ elevation: Elevation) -> some View {
        elevation.layers.reduce(AnyView(self)) { view, layer in
            AnyView(
                view.shadow(
                    color: Color(Elevation.shadowInk).opacity(layer.opacity),
                    radius: layer.radius,
                    y: layer.y
                )
            )
        }
    }
}
