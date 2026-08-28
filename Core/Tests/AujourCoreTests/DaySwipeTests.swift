import Testing

@testable import AujourCore

/// A finger drawn sideways across a day's writing — the way to yesterday that
/// is not the calendar.
///
/// Here rather than in the view for the same reason the pill's travel is:
/// which axis a gesture turned out to be, how much of the finger the day
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

    /// The day moves with the finger, and by less than it — enough to say the
    /// day is being taken somewhere, not so much that it is being dragged off
    /// the screen.
    @Test("the day follows the finger at a fraction of its travel")
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

    /// The one the pill's own drag is at stake in: a finger going down is
    /// pulling the calendar open, and the day underneath must not slide out
    /// from under it because the pull was a degree or two off vertical.
    @Test("a finger going down carries the day nowhere")
    func aFingerGoingDownIsNotThisGesture() {
        var swipe = DaySwipe()

        swipe.dragged(across: 20, down: 60)

        #expect(swipe.axis == .upAndDown)
        #expect(swipe.carried == 0)
    }

    /// And having said which it is, it stays said. A swipe that curled
    /// downward at the end would otherwise stop carrying the day mid-gesture,
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

    /// However far the finger goes: the day is nudged aside and not dragged
    /// off, and a screen an iPad wide has room for a gesture that would carry
    /// it into nothing.
    @Test("the day stops following long before it leaves the screen")
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

    @Test("letting go puts the day back and lets go of the axis")
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
    /// to one that is over would leave the day sitting off to the side.
    @Test("a swipe that is called off puts the day back")
    func aSwipeCanBeCalledOff() {
        var swipe = DaySwipe()
        swipe.dragged(across: -200, down: 0)

        swipe.calledOff()

        #expect(swipe.carried == 0)
        #expect(swipe.axis == nil)
    }

    @Test("where a swipe landed says which way the journal moves")
    func aLandingIsANumberOfDays() {
        #expect(DaySwipe.Landing.theDayBefore.days == -1)
        #expect(DaySwipe.Landing.theDayAfter.days == 1)
        #expect(DaySwipe.Landing.whereItStarted.days == 0)
    }
}
