import Foundation

/// A finger drawn sideways across the date pill: the way to the day before and
/// the day after that does not go through the grid.
///
/// Sideways on the pill steps whatever unit the pill is showing — a week on
/// the week strip, a month on the month grid, and, when it is shut and naming
/// one day, a day. This is that last one, and it is the reason the pill's own
/// gesture has to know which axis it is on: the pill is pulled open downward
/// and walked sideways, from the same finger.
///
/// The pill goes with the finger and comes back rather than one day sliding
/// off while the next slides on. It is a *nudge*: enough travel to say the
/// journal is being moved and which way, and not so much that a pane of glass
/// an inch tall leaves its own lane. Which is why this carries a fraction of
/// the finger rather than all of it — a page-turn would need the day either
/// side laid out, and the pill is sized to the one day it names.
///
/// Here rather than inside the view, like ``DatePill`` and for the same
/// reason: which axis the gesture turned out to be, how far the pill is taken
/// and whether letting go leaves the day are decisions, and a decision inside
/// a `DragGesture` is one nothing can ask about.
public struct DaySwipe: Equatable, Sendable {
    /// The one thing a gesture on the pill can be, once it has moved far
    /// enough to be anything.
    ///
    /// Two gestures live on the pill and share a finger: this, and the pull
    /// that opens it. Whichever way the finger goes first is the gesture it
    /// is, for the whole of it — so a pull down that wanders sideways does not
    /// take the day with it, and a swipe that curls downward at the end does
    /// not open the calendar on its way past.
    public enum Axis: Hashable, Sendable {
        /// The journal being walked a day at a time.
        case sideways

        /// Not this gesture: the pill being pulled open or pushed shut.
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
    /// declared by a tremor — which on this pill would mean a tap that shook
    /// slightly walking the journal off today.
    public static let declaresItself: Double = 10

    /// How much of the finger's travel the pill takes.
    public static let follows: Double = 0.4

    /// How far the pill may be carried out of its lane, however far the finger
    /// goes.
    ///
    /// Small, and a number rather than a fraction of anything: the pill is a
    /// pane of glass a couple of inches wide sitting in the middle of the
    /// screen, and what it has to do is lean towards the day being asked for,
    /// not travel there.
    public static let asFarAs: Double = 44

    /// How far a finger has to have gone — or be going — to leave the day.
    public static let turnsTheDay: Double = 72

    /// Which gesture this is, or `nil` before it has said and once it is over.
    public private(set) var axis: Axis?

    /// How far the finger has gone sideways since the gesture began, and
    /// nought for a gesture that turned out to be the other one.
    ///
    /// Kept as the finger's own travel rather than as the pill's, so that how
    /// far the pill is allowed to lean is a decision about drawing and cannot
    /// reach the decision about which day this lands on.
    private var acrossTheFinger: Double = 0

    public init() {}

    /// Whether a finger is on it right now — what tells the view to follow
    /// rather than to animate.
    public var isBeingDragged: Bool { axis != nil }

    /// How far the pill leans, in points: nought on the day being written, and
    /// towards the finger while one is on it.
    public var carried: Double {
        min(max(acrossTheFinger * Self.follows, -Self.asFarAs), Self.asFarAs)
    }

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
        acrossTheFinger = across
    }

    /// Lets go, and says which day the journal is on now.
    ///
    /// Puts the pill back in its lane either way: the day either side is not
    /// drawn, so there is nothing for the finger to have carried into place.
    /// What a landing changes is which day the pill names, and it slides home
    /// under the new one.
    ///
    /// - Parameter heading: how far the finger was going to get, had it kept
    ///   going — `predictedEndTranslation.width`. Read alongside where it
    ///   actually got to, so that a flick turns the day rather than needing a
    ///   whole thumb's length dragged out across a pill that is not that wide.
    @discardableResult
    public mutating func letGo(heading: Double) -> Landing {
        let wentSideways = axis == .sideways
        let across = acrossTheFinger
        calledOff()

        guard wentSideways else { return .whereItStarted }
        let going = abs(heading) > abs(across) ? heading : across
        guard abs(going) > Self.turnsTheDay else { return .whereItStarted }
        return going < 0 ? .theDayAfter : .theDayBefore
    }

    /// Puts the pill back without deciding anything, for a gesture that was
    /// taken away rather than ended — the view it was on rebuilt, or something
    /// else winning the finger. Without this the pill would be left leaning
    /// with no finger holding it there.
    public mutating func calledOff() {
        axis = nil
        acrossTheFinger = 0
    }
}
