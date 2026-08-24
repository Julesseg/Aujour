import Foundation
import Testing

@testable import AujourCore

// Gathering a day's photographs into the places it stopped is the step that
// makes naming them affordable: it happens over arithmetic, before anything
// has been looked up, and what comes out of it is what gets a name. So what
// has to be right here is which positions count as one place, when the day got
// to each, and that photographs with nothing to say about where they were are
// dropped rather than guessed at.

@Suite("The stops a day's photographs record")
struct PhotographedStopTests {
    // Two well-known Paris cafés, about 60 metres apart, and a museum across
    // the river — near enough to be the same stop and far enough not to be.
    private let flore = Coordinate(latitude: 48.85419, longitude: 2.33262)
    private let magots = Coordinate(latitude: 48.85400, longitude: 2.33330)
    private let orsay = Coordinate(latitude: 48.85995, longitude: 2.32660)

    // MARK: - Which positions are one place

    // The acceptance criterion, and the reason any of this exists: somebody
    // photographs their lunch four times from the same table, and what they
    // would write in their journal is one café.
    @Test("photographs taken in the same spot are one stop")
    func oneSpotIsOneStop() {
        let lunch = (0..<4).map {
            DayPhotograph(
                id: "\($0)",
                takenAt: instant(2026, 3, 9, 12, $0 * 5, in: paris),
                position: flore
            )
        }

        let stops = PhotographedStop.across(lunch)

        #expect(stops.count == 1)
        #expect(stops.first?.photographs == 4)
    }

    // Sixty metres apart is the same corner of Saint-Germain, whatever the two
    // cafés think of each other.
    @Test("positions a stone's throw apart are gathered together")
    func aStonesThrowApart() {
        let stops = PhotographedStop.across([
            photograph(at: flore, 11, 4),
            photograph(at: magots, 11, 20),
        ])

        #expect(stops.count == 1)
    }

    @Test("positions a walk apart are two stops")
    func aWalkApart() {
        let stops = PhotographedStop.across([
            photograph(at: flore, 11, 4),
            photograph(at: orsay, 15, 30),
        ])

        #expect(stops.count == 2)
    }

    // The centre is what gets looked up, so it has to be the middle of what
    // was gathered rather than wherever the first picture was taken from.
    @Test("a stop sits in the middle of its photographs")
    func theMiddleOfThem() {
        let west = Coordinate(latitude: 48.8540, longitude: 2.3320)
        let east = Coordinate(latitude: 48.8540, longitude: 2.3330)

        let stops = PhotographedStop.across([
            photograph(at: west, 11, 0), photograph(at: east, 11, 5),
        ])

        let centre = try! #require(stops.first).centre
        #expect(abs(centre.longitude - 2.3325) < 0.00001)
        #expect(abs(centre.latitude - 48.8540) < 0.00001)
    }

    // A hundred photographs of one café must not drag its centre away from the
    // café: every photograph counts for the same, whether it is the first or
    // the hundredth.
    @Test("the centre is not dragged about by the order the day was walked in")
    func everyPhotographCountsTheSame() {
        let west = Coordinate(latitude: 48.8540, longitude: 2.3320)
        let east = Coordinate(latitude: 48.8540, longitude: 2.3330)

        let manyThenOne = (0..<9).map { photograph(at: west, 11, $0) } + [photograph(at: east, 12, 0)]
        let centre = try! #require(PhotographedStop.across(manyThenOne).first).centre

        // Nine at one end and one at the other sits a tenth of the way along,
        // not halfway.
        #expect(abs(centre.longitude - 2.3321) < 0.00001)
    }

    // MARK: - When the day got there

    // This becomes the time written beside the place — "Café de Flore, 11:04"
    // — and what somebody means by that is when they arrived.
    @Test("a stop is timed by its earliest photograph")
    func timedByTheEarliest() {
        let stops = PhotographedStop.across([
            photograph(at: flore, 13, 30),
            photograph(at: flore, 11, 4),
            photograph(at: flore, 12, 0),
        ])

        #expect(stops.first?.arrivedAt == instant(2026, 3, 9, 11, 4, in: paris))
    }

    // The day reads forward, whatever order the library answered in.
    @Test("the stops come back in the order the day made them")
    func inTheOrderTheDayMadeThem() {
        let stops = PhotographedStop.across([
            photograph(at: orsay, 15, 30),
            photograph(at: flore, 11, 4),
        ])

        #expect(stops.map(\.arrivedAt) == [
            instant(2026, 3, 9, 11, 4, in: paris),
            instant(2026, 3, 9, 15, 30, in: paris),
        ])
    }

    // MARK: - Photographs with nothing to say

    // A screenshot, a picture saved from a message, a camera with location
    // turned off. None of them is a failure and none of them is guessed at.
    @Test("photographs carrying no position are dropped, not guessed at")
    func noPositionAtAll() {
        let stops = PhotographedStop.across([
            DayPhotograph(id: "screenshot", takenAt: instant(2026, 3, 9, 11, 0, in: paris)),
            photograph(at: flore, 11, 4),
        ])

        #expect(stops.count == 1)
        #expect(stops.first?.photographs == 1)
    }

    @Test("a day whose photographs all carry no position records no stops")
    func nothingCarriesAPosition() {
        let stops = PhotographedStop.across([
            DayPhotograph(id: "a", takenAt: instant(2026, 3, 9, 11, 0, in: paris)),
            DayPhotograph(id: "b", takenAt: instant(2026, 3, 9, 12, 0, in: paris)),
        ])

        #expect(stops.isEmpty)
    }

    @Test("a day with no photographs records no stops")
    func noPhotographsAtAll() {
        #expect(PhotographedStop.across([]).isEmpty)
    }

    // MARK: - How far apart is far apart

    // Great-circle metres, the thing the whole grouping is decided in. Checked
    // against a distance that can be looked up rather than one this test made
    // up: the two cafés are about 60 metres apart, and Orsay is most of a
    // kilometre away.
    @Test("how far apart two positions are, in metres")
    func metresApart() {
        #expect(abs(flore.metres(to: magots) - 55) < 15)
        #expect(abs(flore.metres(to: orsay) - 780) < 60)
        #expect(flore.metres(to: flore) == 0)
    }

    private func photograph(at position: Coordinate, _ hour: Int, _ minute: Int) -> DayPhotograph {
        DayPhotograph(
            id: "\(hour):\(minute)",
            takenAt: instant(2026, 3, 9, hour, minute, in: paris),
            position: position
        )
    }
}
