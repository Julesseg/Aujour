import Foundation

/// The header's date pill, as a thing with a position rather than a thing with
/// a state: how far open it is, and what a finger on it does to that.
///
/// Three states — the day on its own, the week around it, the whole month —
/// and one continuous gesture between them, which is why this is a number and
/// not an enum. A pill that only knew which of three states it was in could
/// not follow a finger, and a drag that could not be caught halfway is a drag
/// that cannot be changed your mind about.
///
/// Here rather than inside the view for the reason everything else in Core is:
/// where it settles when it is let go, whether a reversal mid-gesture is
/// honoured, and what counts as a tap rather than a drag are decisions, and a
/// decision living inside a `DragGesture` is one nothing can ask about.
public struct DatePill: Equatable, Sendable {
    /// The three places it comes to rest.
    ///
    /// Numbered, because the number *is* the position: a pill halfway between
    /// the week and the month is at 1.5, and the detent it would settle on is
    /// that rounded.
    public enum Detent: Int, CaseIterable, Comparable, Sendable {
        /// The day, and nothing else.
        case closed = 0

        /// The week the day being written falls in, one row of seven.
        case week = 1

        /// The whole month.
        case month = 2

        public static func < (lhs: Detent, rhs: Detent) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How far a finger has to travel to move it one whole state.
    ///
    /// Not the height the panel grows by, deliberately: the pill opens 0 → 68
    /// points and then 68 → 318, and a gesture pinned to that would be
    /// leisurely for the first state and frantic for the second. One rate for
    /// both is what makes the two steps feel like one gesture.
    public static let travel: Double = 150

    /// How far a finger may move and still have been a tap.
    public static let slop: Double = 4

    /// How far open it is: 0 closed, 1 the week strip, 2 the month grid, and
    /// every value between while a finger is on it.
    public private(set) var progress: Double = 0

    /// Where it started this drag, or `nil` when no finger is on it.
    ///
    /// Kept because a gesture reports the whole journey from where it began
    /// and not the last step of it — which is exactly what makes a drag
    /// reversible, and what a naive `progress += delta` gets wrong.
    private var draggedFrom: Double?

    public init() {}

    /// Whether a finger is on it right now — what tells the view to follow
    /// rather than to animate.
    public var isBeingDragged: Bool { draggedFrom != nil }

    /// The state it is in, or the one it would settle on if it were let go
    /// now.
    public var detent: Detent {
        Detent(rawValue: Int(progress.rounded())) ?? .closed
    }

    /// How far it is from closed towards the week strip, 0 through 1 — and 1
    /// for everything beyond.
    public var openness: Double { min(progress, 1) }

    /// How far it is from the week strip towards the month grid, 0 through 1.
    public var spread: Double { max(0, progress - 1) }

    /// Steps it on: closed, week, month, and back to closed.
    public mutating func tapped() {
        progress = Double((detent.rawValue + 1) % Detent.allCases.count)
    }

    /// Follows a finger.
    ///
    /// - Parameter translation: how far the finger has moved *since the
    ///   gesture began*, downward positive — which is what a gesture reports,
    ///   and what makes going back up unwind rather than pile on.
    public mutating func dragged(by translation: Double) {
        let origin = draggedFrom ?? progress
        draggedFrom = origin
        progress = min(max(origin + translation / Self.travel, 0), Double(Detent.month.rawValue))
    }

    /// Ends the gesture, and decides which gesture it was.
    ///
    /// A tap and a drag arrive as the same finger, so the difference is
    /// settled here rather than by two gestures competing for it: a finger
    /// that stayed put stepped the pill on, and one that moved leaves it at
    /// the state it is nearest.
    ///
    /// - Parameter translation: the whole distance the finger covered.
    public mutating func letGo(afterMoving translation: Double) {
        let origin = draggedFrom
        draggedFrom = nil
        guard abs(translation) > Self.slop else {
            // Put back where the finger found it before stepping on, so that a
            // tap that wobbled a point or two steps from the state it was in
            // rather than from a fraction of one.
            if let origin { progress = origin }
            tapped()
            return
        }
        progress = progress.rounded()
    }

    /// Shuts it. What picking a day does — the day is chosen, so the grid it
    /// was chosen from has nothing left to say.
    public mutating func close() {
        draggedFrom = nil
        progress = 0
    }
}
