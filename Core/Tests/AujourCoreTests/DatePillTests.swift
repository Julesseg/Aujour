import Testing

@testable import AujourCore

/// The header's date pill, as the thing that moves: closed, a week, a month,
/// and the one gesture that goes between them.
///
/// All of it is here rather than in the view because none of it is drawing.
/// Which state a finger has left the pill in, whether a reversal mid-gesture
/// is honoured, and where it lands when it is let go are decisions, and a
/// decision that only exists inside a `DragGesture` is one nothing can ask
/// about.
@Suite("The date pill")
struct DatePillTests {
    @Test("it starts closed, showing nothing but the day")
    func itStartsClosed() {
        let pill = DatePill()

        #expect(pill.progress == 0)
        #expect(pill.detent == .closed)
        #expect(!pill.isBeingDragged)
    }

    /// The pill opens on a tap and then goes back and forth between the two
    /// things it has to show. Tapping never shuts it: the way out is the day's
    /// own words behind it, and picking a day out of the grid.
    @Test("tapping opens it, and then goes between the week and the month")
    func tappingGoesBetweenTheWeekAndTheMonth() {
        var pill = DatePill()

        pill.tapped()
        #expect(pill.detent == .week)

        pill.tapped()
        #expect(pill.detent == .month)

        pill.tapped()
        #expect(pill.detent == .week)

        pill.tapped()
        #expect(pill.detent == .month)
    }

    @Test("a drag downward opens it by however far the finger went")
    func draggingFollowsTheFinger() {
        var pill = DatePill()

        pill.dragged(by: DatePill.travel / 2)

        #expect(pill.progress == 0.5)
        #expect(pill.isBeingDragged)
    }

    /// The one that a gesture written against the *last* frame's translation
    /// gets wrong: a finger that goes down and then comes back up has to
    /// unwind, and each `onChanged` carries the whole journey rather than the
    /// last step of it.
    @Test("a drag reversed mid-gesture comes back with the finger")
    func aDragCanBeReversedMidGesture() {
        var pill = DatePill()

        pill.dragged(by: DatePill.travel * 1.5)
        #expect(pill.progress == 1.5)

        pill.dragged(by: DatePill.travel * 0.25)
        #expect(pill.progress == 0.25)
    }

    @Test("a drag that starts from an open pill starts from where it was")
    func aDragResumesFromTheStateItIsIn() {
        var pill = DatePill()
        pill.tapped()

        pill.dragged(by: DatePill.travel / 2)

        #expect(pill.progress == 1.5)
    }

    @Test("dragging up from an open pill closes it")
    func draggingUpwardsCloses() {
        var pill = DatePill()
        pill.tapped()
        pill.tapped()

        pill.dragged(by: -DatePill.travel * 2)
        pill.letGo(afterMoving: -DatePill.travel * 2)

        #expect(pill.detent == .closed)
    }

    @Test("no drag takes it past either end")
    func theDragIsBoundedByTheTwoEnds() {
        var pill = DatePill()

        pill.dragged(by: DatePill.travel * 9)
        #expect(pill.progress == 2)

        pill.letGo(afterMoving: DatePill.travel * 9)
        pill.dragged(by: -DatePill.travel * 9)
        #expect(pill.progress == 0)
    }

    /// The whole of "releasing mid-drag settles to the nearest state rather
    /// than staying between two".
    @Test(
        "letting go settles on the nearest state",
        arguments: [
            (dragged: 0.4, settled: DatePill.Detent.closed),
            (dragged: 0.6, settled: .week),
            (dragged: 1.4, settled: .week),
            (dragged: 1.6, settled: .month),
        ]
    )
    func lettingGoSettlesOnTheNearestState(dragged: Double, settled: DatePill.Detent) {
        var pill = DatePill()

        pill.dragged(by: DatePill.travel * dragged)
        pill.letGo(afterMoving: DatePill.travel * dragged)

        #expect(pill.detent == settled)
        #expect(pill.progress == Double(settled.rawValue))
        #expect(!pill.isBeingDragged)
    }

    /// A tap and a drag are the same gesture arriving, so which one it was is
    /// decided here and not by two gestures competing for the same finger.
    @Test("a finger that barely moved was a tap, not a drag that went nowhere")
    func aFingerThatBarelyMovedIsATap() {
        var pill = DatePill()

        pill.dragged(by: DatePill.slop)
        pill.letGo(afterMoving: DatePill.slop)

        #expect(pill.detent == .week)
    }

    @Test("a tap from between two states steps on from the nearer one")
    func aTapFromMidFlightStepsFromTheNearestState() {
        var pill = DatePill()
        pill.dragged(by: DatePill.travel * 1.4)
        pill.letGo(afterMoving: DatePill.travel * 1.4)

        pill.tapped()

        #expect(pill.detent == .month)
    }

    /// A gesture is not always ended: it can be taken away, when the view it
    /// is on is rebuilt or something else wins the finger, and then no `letGo`
    /// arrives at all. What must not survive that is where the drag began —
    /// the next one would start from there instead of from where the pill now
    /// is, and jump a state or two on the first frame.
    @Test("a drag that is never let go does not anchor the next one")
    func anAbandonedDragDoesNotAnchorTheNextOne() {
        var pill = DatePill()

        // Opened all the way by a drag that is then taken away mid-flight.
        pill.dragged(by: DatePill.travel * 2)
        #expect(pill.detent == .month)

        // Tapped back to the week.
        pill.tapped()
        #expect(pill.detent == .week)
        #expect(!pill.isBeingDragged)

        // And a fresh drag moves it by its own distance from where the pill
        // now is. Still anchored to the abandoned drag, this would start from
        // the closed pill that one began on and land a whole state short.
        pill.dragged(by: DatePill.travel)
        #expect(pill.progress == 2)
    }

    @Test("picking a day shuts it, wherever it had been left")
    func closingPutsItBack() {
        var pill = DatePill()
        pill.dragged(by: DatePill.travel * 1.7)

        pill.close()

        #expect(pill.progress == 0)
        #expect(pill.detent == .closed)
        #expect(!pill.isBeingDragged)
    }

    /// Two numbers the view draws every part of the pill from, so that
    /// "how far between these two states is it" is asked once.
    @Test("how far open it is is read in two halves, each of them a fraction")
    func opennessAndSpreadSplitTheTravel() {
        var pill = DatePill()

        #expect(pill.openness == 0)
        #expect(pill.spread == 0)

        pill.dragged(by: DatePill.travel * 0.5)
        #expect(pill.openness == 0.5)
        #expect(pill.spread == 0)

        pill.dragged(by: DatePill.travel * 1.5)
        #expect(pill.openness == 1)
        #expect(pill.spread == 0.5)
    }
}
