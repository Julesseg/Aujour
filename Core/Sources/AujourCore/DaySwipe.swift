import Foundation

/// A finger drawn sideways across a day's writing: the way to the day before
/// and the day after that does not go through the calendar.
///
/// The day follows the finger and comes back, rather than sliding off one side
/// while the next day slides on. It is a *nudge*: enough travel to say the
/// journal is being moved and where to, and not so much that the words being
/// written leave the screen. Which is why this carries a fraction of the
/// finger rather than all of it — a page-turn would need the day either side
/// laid out, and there is only ever one editor over one Entry.
///
/// Here rather than inside the view, like ``DatePill`` and for the same
/// reason: which axis the gesture turned out to be, how far the day is taken
/// and whether letting go leaves the day are decisions, and a decision inside
/// a `DragGesture` is one nothing can ask about.
public struct DaySwipe: Equatable, Sendable {
    /// The one thing a gesture over a day's words can be, once it has moved
    /// far enough to be anything.
    ///
    /// Two gestures live on this screen and share a finger: this, and the pull
    /// that opens the date pill. Whichever way the finger goes first is the
    /// gesture it is, for the whole of it — so a pull down that wanders
    /// sideways does not take the day with it, and a swipe that curls downward
    /// at the end still turns the day.
    public enum Axis: Hashable, Sendable {
        /// The journal being moved a day.
        case sideways

        /// Not this gesture: the pill being pulled open, or the day's own
        /// words being scrolled.
        case upAndDown
    }

    /// Where a swipe let go.
    public enum Landing: Hashable, Sendable {
        case theDayBefore
        case theDayAfter

        /// The day it started on: a swipe too short, or too crooked, to have
        /// meant it.
        case whereItStarted

        /// Which way the journal moves, as a number of days.
        public var days: Int {
            switch self {
            case .theDayBefore: -1
            case .theDayAfter: 1
            case .whereItStarted: 0
            }
        }
    }

    /// How far a finger travels before it has said which gesture it is.
    ///
    /// Not zero, because no finger goes exactly along an axis: the first few
    /// points of any gesture are noise, and a swipe declared off them would be
    /// declared by a tremor.
    public static let declaresItself: Double = 10

    /// How much of the finger's travel the day takes.
    public static let follows: Double = 0.4

    /// How far the day may be carried, however far the finger goes.
    ///
    /// A number and not a fraction of the screen: the day is nudged aside so
    /// that the movement is legible, and on a screen an iPad wide a fraction
    /// would let one gesture carry the words being written clean off it.
    public static let asFarAs: Double = 120

    /// How far a finger has to have gone — or be going — to leave the day.
    public static let turnsTheDay: Double = 72

    /// Which gesture this is, or `nil` before it has said and once it is over.
    public private(set) var axis: Axis?

    /// How far the day has been carried, in points: nought on the day being
    /// written, and towards the finger while one is on it.
    public private(set) var carried: Double = 0

    public init() {}

    /// Whether a finger is on it right now — what tells the view to follow
    /// rather than to animate.
    public var isBeingDragged: Bool { axis != nil }

    /// Follows a finger.
    ///
    /// - Parameters:
    ///   - across: how far the finger has moved sideways *since the gesture
    ///     began*, rightward positive — which is what a gesture reports, and
    ///     what makes turning back unwind rather than pile on.
    ///   - down: the same, downward positive. Read only to decide which
    ///     gesture this is, and only once.
    public mutating func dragged(across: Double, down: Double) {
        if axis == nil {
            guard max(abs(across), abs(down)) >= Self.declaresItself else { return }
            axis = abs(across) > abs(down) ? .sideways : .upAndDown
        }
        guard axis == .sideways else { return }
        carried = min(max(across * Self.follows, -Self.asFarAs), Self.asFarAs)
    }

    /// Lets go, and says which day the journal is on now.
    ///
    /// Puts the day back where it started either way: the day either side is
    /// not drawn, so there is nothing for the finger to have carried into
    /// place. What a landing changes is which day the editor is over, and the
    /// day slides home under whatever arrives there.
    ///
    /// - Parameter heading: how far the finger was going to get, had it kept
    ///   going — `predictedEndTranslation.width`. Read alongside where it
    ///   actually got to, so that a flick turns the day rather than needing a
    ///   whole thumb's length dragged out.
    @discardableResult
    public mutating func letGo(heading: Double) -> Landing {
        let wentSideways = axis == .sideways
        let travelled = carried / Self.follows
        calledOff()

        guard wentSideways else { return .whereItStarted }
        let going = abs(heading) > abs(travelled) ? heading : travelled
        guard abs(going) > Self.turnsTheDay else { return .whereItStarted }
        return going < 0 ? .theDayAfter : .theDayBefore
    }

    /// Puts the day back without deciding anything, for a gesture that was
    /// taken away rather than ended — the view it was on rebuilt, or something
    /// else winning the finger. Without this the day would be left sitting off
    /// to one side with no finger holding it there.
    public mutating func calledOff() {
        axis = nil
        carried = 0
    }
}
