import AujourCore

/// A device that is nudged rather than rung: what it was last asked to hold,
/// and how many times it has been asked anything.
///
/// Shared by every suite in this target that reaches the reminder — what is
/// pending and whether the device was ever asked are the two things all of
/// them look at, and a second copy of this would be two doubles drifting apart
/// about one seam.
///
/// Unchecked because a test drives it from the main actor and nowhere else,
/// while the seam it stands in for is one the app reaches from anywhere.
final class ADeviceToNudge: Nudges, @unchecked Sendable {
    private(set) var booked: [Nudge] = []
    private(set) var bookings = 0
    private(set) var timesAsked = 0

    /// Undecided until it is asked, like a device nobody has answered for yet
    /// — which is what makes "choosing a time is what asks" a thing a test can
    /// see happen.
    private var permission: NudgeAccess = .undecided

    /// What it says when it is asked. Allowed unless a test is about the
    /// answer that leaves a reminder unable to arrive.
    private let answering: NudgeAccess

    init(answering: NudgeAccess = .allowed) {
        self.answering = answering
    }

    func access() async -> NudgeAccess { permission }

    func ask() async -> NudgeAccess {
        timesAsked += 1
        permission = answering
        return permission
    }

    func book(_ nudges: [Nudge]) async {
        booked = nudges
        bookings += 1
    }
}
