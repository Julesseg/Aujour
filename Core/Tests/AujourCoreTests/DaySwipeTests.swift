import Testing

@testable import AujourCore

/// A finger drawn sideways across the date pill — the way to yesterday that is
/// not the grid.
///
/// Here rather than in the view for the same reason the pill's travel is:
/// which axis a gesture turned out to be, how much of the finger the pill
/// takes, and whether letting go leaves the day or puts it back are decisions,
/// and a decision inside a `DragGesture` is one nothing can ask about. A
/// synthesized drag is also the wrong instrument for arithmetic.
@Suite("Swiping between days")
struct DaySwipeTests {
    @Test("it starts on the day it is on, with no finger on it")
    func itStartsStill() {
        let swipe = DaySwipe()

        #expect(swipe.carried == 0)
        #expect(!swipe.isBeingDragged)
    }

    /// The pill moves with the finger, and by less than it — enough to say the
    /// journal is being taken somewhere, not so much that a pane of glass an
    /// inch tall leaves its own lane.
    @Test("the pill follows the finger at a fraction of its travel")
    func theDayFollowsTheFinger() {
        var swipe = DaySwipe()

        swipe.dragged(across: 100, down: 0)

        #expect(swipe.isBeingDragged)
        #expect(swipe.carried == 100 * DaySwipe.follows)
        #expect(swipe.carried < 100)
    }

    @Test("a finger that has barely moved has not said which gesture it is")
    func aFingerThatHasBarelyMovedDeclaresNothing() {
        var swipe = DaySwipe()

        swipe.dragged(across: DaySwipe.declaresItself - 1, down: 0)

        #expect(!swipe.isBeingDragged)
        #expect(swipe.carried == 0)
    }

    /// The one the pill's own drag is at stake in: a finger going down the
    /// pill is pulling the calendar open, and the journal must not walk off
    /// today because the pull was a degree or two off vertical.
    @Test("a finger going down carries the pill nowhere")
    func aFingerGoingDownIsNotThisGesture() {
        var swipe = DaySwipe()

        swipe.dragged(across: 20, down: 60)

        #expect(swipe.axis == .upAndDown)
        #expect(swipe.carried == 0)
    }

    /// And having said which it is, it stays said. A swipe that curled
    /// downward at the end would otherwise stop carrying the pill mid-gesture,
    /// and a pull that wandered sideways would start.
    @Test("the axis a gesture declares first is the one it keeps")
    func theAxisIsDeclaredOnce() {
        var sideways = DaySwipe()
        sideways.dragged(across: 40, down: 0)
        sideways.dragged(across: 45, down: 300)

        #expect(sideways.axis == .sideways)
        #expect(sideways.carried == 45 * DaySwipe.follows)

        var downward = DaySwipe()
        downward.dragged(across: 0, down: 40)
        downward.dragged(across: 300, down: 45)

        #expect(downward.axis == .upAndDown)
        #expect(downward.carried == 0)
    }

    /// However far the finger goes: the pill leans towards the day being asked
    /// for rather than travelling there, and a screen an iPad wide has room
    /// for a gesture that would carry it clean out of its lane.
    @Test("the pill stops following long before it leaves its lane")
    func theDayIsNudgedAndNotDraggedOff() {
        var swipe = DaySwipe()

        swipe.dragged(across: 2000, down: 0)
        #expect(swipe.carried == DaySwipe.asFarAs)

        swipe.dragged(across: -2000, down: 0)
        #expect(swipe.carried == -DaySwipe.asFarAs)
    }

    @Test("a swipe leftwards lands on the day after, and rightwards on the day before")
    func aSwipeLandsOnTheDayEitherSide() {
        var leftwards = DaySwipe()
        leftwards.dragged(across: -DaySwipe.turnsTheDay - 1, down: 0)

        #expect(leftwards.letGo(heading: -DaySwipe.turnsTheDay - 1) == .theDayAfter)

        var rightwards = DaySwipe()
        rightwards.dragged(across: DaySwipe.turnsTheDay + 1, down: 0)

        #expect(rightwards.letGo(heading: DaySwipe.turnsTheDay + 1) == .theDayBefore)
    }

    @Test("a short swipe puts the day back rather than leaving it")
    func aShortSwipeComesBack() {
        var swipe = DaySwipe()
        swipe.dragged(across: DaySwipe.turnsTheDay - 1, down: 0)

        #expect(swipe.letGo(heading: DaySwipe.turnsTheDay - 1) == .whereItStarted)
    }

    /// Read off where the finger was going and not only where it got to, so
    /// that a flick turns the day rather than needing a whole thumb's length
    /// dragged out — which is the difference between a gesture and a threshold
    /// somebody has to find.
    @Test("a flick turns the day even though the finger stopped short")
    func aFlickTurnsTheDay() {
        var swipe = DaySwipe()
        swipe.dragged(across: -30, down: 0)

        #expect(swipe.letGo(heading: -400) == .theDayAfter)
    }

    @Test("a finger that went down and flicked sideways at the end turns nothing")
    func aDownwardGestureNeverTurnsTheDay() {
        var swipe = DaySwipe()
        swipe.dragged(across: 0, down: 40)

        #expect(swipe.letGo(heading: 400) == .whereItStarted)
    }

    @Test("letting go puts the pill back and lets go of the axis")
    func lettingGoPutsTheDayBack() {
        var swipe = DaySwipe()
        swipe.dragged(across: -200, down: 0)

        _ = swipe.letGo(heading: -200)

        #expect(swipe.carried == 0)
        #expect(!swipe.isBeingDragged)
        #expect(swipe.axis == nil)
    }

    /// A gesture can be taken away rather than ended — the view it is on is
    /// rebuilt, or something else wins the finger — and a swipe still anchored
    /// to one that is over would leave the pill leaning with nothing holding
    /// it.
    @Test("a swipe that is called off puts the pill back")
    func aSwipeCanBeCalledOff() {
        var swipe = DaySwipe()
        swipe.dragged(across: -200, down: 0)

        swipe.calledOff()

        #expect(swipe.carried == 0)
        #expect(swipe.axis == nil)
    }

    /// The one a clamp written into the wrong place breaks: how far the pill
    /// is *allowed to lean* is a decision about drawing, and a swipe far
    /// enough to hit that ceiling has to go on being read as the long swipe it
    /// was.
    @Test("a swipe past the pill's own ceiling still lands on the day it meant")
    func theLeanCeilingDoesNotReachTheLanding() {
        var swipe = DaySwipe()
        swipe.dragged(across: -900, down: 0)
        #expect(swipe.carried == -DaySwipe.asFarAs)

        // Let go standing still, so nothing but the travel itself can carry
        // the decision.
        #expect(swipe.letGo(heading: 0) == .theDayAfter)
    }

    @Test("where a swipe landed says which way the journal moves")
    func aLandingIsANumberOfDays() {
        #expect(DaySwipe.Landing.theDayBefore.days == -1)
        #expect(DaySwipe.Landing.theDayAfter.days == 1)
        #expect(DaySwipe.Landing.whereItStarted.days == 0)
    }
}
