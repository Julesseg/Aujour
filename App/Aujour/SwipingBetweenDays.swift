import AujourCore
import SwiftUI

extension View {
    /// Lets a finger drawn sideways across a day take the journal to the day
    /// either side of it.
    ///
    /// The way through the journal that is not the calendar: yesterday is one
    /// gesture away rather than a pill opened, a grid read and a cell aimed
    /// at. The day follows the finger and springs home; what a landing changes
    /// is which day the screen is over.
    ///
    /// A modifier because it belongs to whichever day is on screen and there
    /// are two kinds of those — an Entry being written, and a day that has not
    /// arrived — and a swipe has to work on both, or the second would be a
    /// page a finger could reach and not leave.
    ///
    /// Where the day settles, what counts as a swipe rather than a pull, and
    /// which day it lands on are ``DaySwipe``'s in Core. All this adds is the
    /// finger.
    ///
    /// - Parameter turn: which way the journal moves, as a number of days.
    func swipingBetweenDays(turning turn: @escaping (Int) -> Void) -> some View {
        modifier(SwipingBetweenDays(turn: turn))
    }
}

/// The finger, and nothing else.
///
/// Simultaneous rather than in front of what it is over, and that is the whole
/// gesture arrangement here. The day is written in a text view that scrolls,
/// puts a caret where it is tapped and drags a selection; a gesture that took
/// the finger away from it first would be a swipe that cost the app its
/// editor. So both run, and which one this turns out to be is decided by where
/// the finger went — a `DaySwipe` that has declared itself vertical carries
/// nothing and lands nowhere, whatever the rest of the gesture does.
///
/// Which is also how it keeps out of the date pill's way. The pill is drawn
/// over this and takes its own finger; a pull that starts on the page below it
/// and goes down is the day's words being scrolled, and this stays out of it
/// for the whole of that gesture rather than for the first few points of it.
private struct SwipingBetweenDays: ViewModifier {
    let turn: (Int) -> Void

    @State private var swipe = DaySwipe()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(x: swipe.carried)
            // While a finger is on it there is nothing to animate: the day is
            // wherever the finger left it. The spring is only for the settling.
            .animation(swipe.isBeingDragged ? nil : settle, value: swipe.carried)
            .simultaneousGesture(
                // Not zero, so that a tap aimed at a word is a tap and not the
                // shortest possible drag. Which gesture it is once it *has*
                // moved is Core's to say, and not a distance SwiftUI is given
                // here — a `minimumDistance` that gated this would be the axis
                // being declared twice, in two places, by two rules.
                DragGesture(minimumDistance: 1)
                    .onChanged { finger in
                        swipe.dragged(
                            across: finger.translation.width,
                            down: finger.translation.height
                        )
                    }
                    .onEnded { finger in
                        let landing = swipe.letGo(heading: finger.predictedEndTranslation.width)
                        guard landing != .whereItStarted else { return }
                        turn(landing.days)
                    }
            )
    }

    /// The identity's own settle, or a plain short fade for a reader who asked
    /// for less movement — the same one the pill lands with.
    private var settle: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .interpolatingSpring(stiffness: 320, damping: 30)
    }
}
