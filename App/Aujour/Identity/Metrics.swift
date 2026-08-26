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

    /// A surface floating over content that scrolls under it: a banner, the
    /// date pill, a toolbar.
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
                    color: Color(UIColor(identity: 0x241F1B)).opacity(layer.opacity),
                    radius: layer.radius,
                    y: layer.y
                )
            )
        }
    }
}
