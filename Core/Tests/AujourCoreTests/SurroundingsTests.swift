import Foundation
import Testing

@testable import AujourCore

// What the device says about where it is gets asked two different questions,
// and they have two different answers. "What shall I offer you for today" is a
// list, led by the town, because confirming the offer is one tap and the town
// is right on every day of the year. "What is this one place" is a single name
// for somewhere the user is not — a position out of one of the day's
// photographs — and there the specific name has been earned.
//
// Both are decided here, in metres a test can name, rather than wherever
// CoreLocation happened to leave things: what a single confirming tap writes
// into somebody's journal is not a thing to work out by standing in a café.

@Suite("What the places around a fix are worth offering")
struct SurroundingsTests {
    private let flore = Place(id: "flore", name: "Café de Flore", region: "Paris")
    private let pharmacy = Place(id: "pharmacy", name: "Pharmacie du Marché", region: "Paris")
    private let town = Place(id: "paris", name: "Paris")

    // MARK: - The list offered for today

    // Confirming the offer is one tap, so the offer has to be somewhere the
    // user certainly was. Standing in the café, "Paris" is still true; the
    // café is one tap down the list for the days it is the answer.
    @Test("the town leads, however close the nearest named place is")
    func theTownLeads() {
        let here = Surroundings(
            named: [NearbyPlace(place: flore, metresAway: 8)],
            area: town
        )

        #expect(here.toOffer == [town, flore])
    }

    // And the case the rule was always really about: a pharmacy fifty doors
    // along is a place somebody may only have walked past, and a wrong answer
    // written into somebody's journal is the one thing this must never do.
    @Test("a named place merely nearby never leads")
    func merelyNearby() {
        let here = Surroundings(
            named: [NearbyPlace(place: pharmacy, metresAway: 240)],
            area: town
        )

        #expect(here.toOffer == [town, pharmacy])
    }

    // Nearest first behind the town, which is the seam's promise about the
    // order it hands them over in.
    @Test("the named places follow the town in the order they were given")
    func inTheOrderGiven() {
        let here = Surroundings(
            named: [
                NearbyPlace(place: flore, metresAway: 8),
                NearbyPlace(place: pharmacy, metresAway: 240),
            ],
            area: town
        )

        #expect(here.toOffer == [town, flore, pharmacy])
    }

    // A list somebody reads at a glance while a sentence waits, not a
    // directory of everything with a name within a couple of minutes' walk.
    @Test("no more than five places are offered, the town among them")
    func fiveAtMost() {
        let crowded = Surroundings(
            named: (0..<20).map {
                NearbyPlace(
                    place: Place(id: "\($0)", name: "Place \($0)"),
                    metresAway: Double($0) * 10
                )
            },
            area: town
        )

        #expect(crowded.toOffer.count == 5)
        #expect(crowded.toOffer.first == town)
        // The four nearest, and the fifteen further off dropped.
        #expect(crowded.toOffer.dropFirst().map(\.name) == [
            "Place 0", "Place 1", "Place 2", "Place 3",
        ])
    }

    // The cap holds where there is no town to spend a row on, and what it
    // keeps is still the nearest.
    @Test("a device that could not name the town still offers no more than five")
    func fiveAtMostWithoutATown() {
        let crowded = Surroundings(
            named: (0..<20).map {
                NearbyPlace(
                    place: Place(id: "\($0)", name: "Place \($0)"),
                    metresAway: Double($0) * 10
                )
            }
        )

        #expect(crowded.toOffer.map(\.name) == [
            "Place 0", "Place 1", "Place 2", "Place 3", "Place 4",
        ])
    }

    // A house in the countryside: no shop, no station, nothing with a name of
    // its own for a mile. The town is the whole answer, and it is a good one.
    @Test("somewhere with no named place at all is offered its town")
    func nowhereWithAName() {
        #expect(Surroundings(area: town).toOffer == [town])
    }

    // And the other way round: a device that found the café but could put no
    // name to the town offers the café, however far off it is. There is
    // nothing safer to lead with.
    @Test("a town the device could not name leaves the named places to lead")
    func noTownAtAll() {
        let close = Surroundings(named: [NearbyPlace(place: flore, metresAway: 8)])
        #expect(close.toOffer == [flore])

        let farOff = Surroundings(named: [NearbyPlace(place: pharmacy, metresAway: 240)])
        #expect(farOff.toOffer == [pharmacy])
    }

    @Test("a device that could say nothing at all offers nothing at all")
    func nothingAtAll() {
        #expect(Surroundings().toOffer.isEmpty)
    }

    // MARK: - The one name a photographed spot is called

    // Somebody stood there and took a picture, so a café a few metres off is
    // where they were rather than somewhere they might have walked past. This
    // is the whole reason a day of photographs comes back as a day of places
    // rather than the town over and over.
    @Test("a named place the picture was taken in is what the spot is called")
    func takenInsideOne() {
        let there = Surroundings(
            named: [NearbyPlace(place: flore, metresAway: 8)],
            area: town
        )

        #expect(there.bestKnownAs == flore)
    }

    // Past arm's reach there is no such claim, and the town takes over.
    @Test("a named place merely near the picture gives way to the town")
    func takenNearOne() {
        let there = Surroundings(
            named: [NearbyPlace(place: pharmacy, metresAway: 240)],
            area: town
        )

        #expect(there.bestKnownAs == town)
    }

    // The edge of the rule, named in metres so that moving it is a decision
    // somebody makes rather than one that happens.
    @Test("arm's reach is a hundred metres, and its own edge counts as inside")
    func theEdgeOfArmsReach() {
        let onTheLine = Surroundings(
            named: [NearbyPlace(place: flore, metresAway: 100)],
            area: town
        )
        #expect(onTheLine.bestKnownAs == flore)

        let justPast = Surroundings(
            named: [NearbyPlace(place: flore, metresAway: 100.5)],
            area: town
        )
        #expect(justPast.bestKnownAs == town)
    }

    // Nothing safer to fall back on: a spot with a name and no town is called
    // by that name, however far off it was.
    @Test("a spot with no town is called by the nearest name there is")
    func noTownToFallBackOn() {
        let there = Surroundings(named: [NearbyPlace(place: pharmacy, metresAway: 240)])

        #expect(there.bestKnownAs == pharmacy)
    }

    @Test("a spot with nothing around it is called nothing")
    func nothingAroundIt() {
        #expect(Surroundings().bestKnownAs == nil)
    }

    @Test("a spot with only a town is called by the town")
    func onlyATown() {
        #expect(Surroundings(area: town).bestKnownAs == town)
    }
}
