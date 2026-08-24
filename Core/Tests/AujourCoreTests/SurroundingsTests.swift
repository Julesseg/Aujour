import Foundation
import Testing

@testable import AujourCore

// Which of the places around somebody the widget puts in the field, and which
// ones sit under it. The one real judgement in {{location}}, and the one that
// decides what a single confirming tap writes into a journal — so it is
// decided here, in metres a test can name, rather than wherever CoreLocation
// happened to leave things.

@Suite("The place a widget leads with")
struct SurroundingsTests {
    private let flore = Place(id: "flore", name: "Café de Flore", region: "Paris")
    private let pharmacy = Place(id: "pharmacy", name: "Pharmacie du Marché", region: "Paris")
    private let quarter = Place(id: "quarter", name: "Saint-Germain-des-Prés", region: "Paris")

    // Sitting in the café. The specific name is what somebody means by where
    // they were, and the neighbourhood is the second thing on the list.
    @Test("a named place you are standing in leads, and the area comes after it")
    func standingInOne() {
        let here = Surroundings(
            named: [NearbyPlace(place: flore, metresAway: 8)],
            area: quarter
        )

        #expect(here.toOffer == [flore, quarter])
    }

    // Walking down the street with a pharmacy fifty doors along. Confirming
    // the offer is one tap, so the offer must not be somewhere the user has
    // never been — the area is vague and right, which beats specific and
    // wrong.
    @Test("a named place merely nearby does not lead — the area does")
    func merelyNearby() {
        let here = Surroundings(
            named: [NearbyPlace(place: pharmacy, metresAway: 240)],
            area: quarter
        )

        #expect(here.toOffer == [quarter, pharmacy])
    }

    // Nothing is dropped either way: what does not lead is one tap down the
    // picker.
    @Test("everything found is offered, whichever leads")
    func nothingIsDropped() {
        let close = Surroundings(
            named: [
                NearbyPlace(place: flore, metresAway: 8),
                NearbyPlace(place: pharmacy, metresAway: 240),
            ],
            area: quarter
        )
        #expect(close.toOffer == [flore, quarter, pharmacy])

        let farOff = Surroundings(
            named: [
                NearbyPlace(place: pharmacy, metresAway: 240),
                NearbyPlace(place: flore, metresAway: 300),
            ],
            area: quarter
        )
        #expect(farOff.toOffer == [quarter, pharmacy, flore])
    }

    // A house in the countryside: no shop, no station, nothing with a name of
    // its own for a mile. The area is the whole answer, and it is a good one.
    @Test("somewhere with no named place at all is offered its area")
    func nowhereWithAName() {
        let here = Surroundings(area: quarter)

        #expect(here.toOffer == [quarter])
    }

    // And the other way round: a device that found the café but could put no
    // name to the area offers the café, however far off it is. There is
    // nothing safer to lead with.
    @Test("an area the device could not name leaves the named places to lead")
    func noAreaAtAll() {
        let close = Surroundings(named: [NearbyPlace(place: flore, metresAway: 8)])
        #expect(close.toOffer == [flore])

        let farOff = Surroundings(named: [NearbyPlace(place: pharmacy, metresAway: 240)])
        #expect(farOff.toOffer == [pharmacy])
    }

    @Test("a device that could say nothing at all offers nothing at all")
    func nothingAtAll() {
        #expect(Surroundings().toOffer.isEmpty)
    }

    // The edge of the rule, named in metres so that moving it is a decision
    // somebody makes rather than one that happens.
    @Test("arm's reach is a hundred metres, and its own edge counts as inside")
    func theEdgeOfArmsReach() {
        let onTheLine = Surroundings(
            named: [NearbyPlace(place: flore, metresAway: 100)],
            area: quarter
        )
        #expect(onTheLine.toOffer == [flore, quarter])

        let justPast = Surroundings(
            named: [NearbyPlace(place: flore, metresAway: 100.5)],
            area: quarter
        )
        #expect(justPast.toOffer == [quarter, flore])
    }
}
