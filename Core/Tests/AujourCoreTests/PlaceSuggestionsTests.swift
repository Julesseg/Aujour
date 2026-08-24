import Foundation
import Testing

@testable import AujourCore

// What the {{location}} widget has to get right is which place it offers, when
// it should offer nothing at all, and that nothing about a device that will
// not say where it is ever reaches the user as a question they cannot answer.
// All of it is decided here, over places that are said rather than found — the
// permission alert and CoreLocation are the app's, and neither is a thing this
// module has ever seen.

@MainActor
@Suite("The places a location widget offers")
struct PlaceSuggestionsTests {
    private let flore = Place(id: "flore", name: "Café de Flore", region: "Paris")
    private let deuxMagots = Place(id: "magots", name: "Les Deux Magots", region: "Paris")

    // MARK: - What is offered

    // Nearest first, and in the order the device gave them: which place is
    // closest is a fact about where somebody is standing, and this is the part
    // that knows about widgets and not about distances.
    @Test("the places around the device are offered in the order it named them")
    func thePlacesAround() async {
        let around = SomePlaces(holding: [flore, deuxMagots])

        let suggestions = PlaceSuggestions(from: around)
        await suggestions.look()

        #expect(suggestions.state == .offering([flore, deuxMagots]))
    }

    // The first of them is the offer, and the rest are what tapping "change"
    // is for. Both come out of one reading, because they are one answer.
    @Test("the first place found is the one on offer")
    func theOneOnOffer() async {
        let suggestions = PlaceSuggestions(from: SomePlaces(holding: [flore, deuxMagots]))
        await suggestions.look()

        #expect(suggestions.offered == flore)
    }

    @Test("nothing is on offer until something has been found")
    func nothingOnOfferYet() async {
        let suggestions = PlaceSuggestions(from: SomePlaces(holding: [], access: .undecided))
        await suggestions.look()

        #expect(suggestions.offered == nil)
    }

    // A field in the countryside, a device with the radios off, a lookup that
    // came back with nothing: none of them is a failure, and all of them are
    // the same thing to a widget — no place to offer, and a question still
    // answerable by typing one.
    @Test("somewhere the device can name no place is nothing to offer")
    func nowhereTheDeviceCanName() async {
        let suggestions = PlaceSuggestions(from: SomePlaces(holding: []))
        await suggestions.look()

        #expect(suggestions.state == .nothingToOffer)
    }

    // What a preview and every test of something else get.
    @Test("no places behind it at all is nothing to offer, and nothing asked")
    func noPlacesAtAll() async {
        let suggestions = PlaceSuggestions()
        await suggestions.look()
        await suggestions.askToLook()

        #expect(suggestions.state == .nothingToOffer)
    }

    // MARK: - The permission

    // Opening the sheet asks the device nothing. It says there is somewhere
    // worth looking, and the looking happens because the user said so — which
    // is what keeps a system alert out from in front of somebody who only
    // tapped a word in their own sentence.
    @Test("a device nobody has been asked about is offered to look at, not read")
    func nobodyAskedYet() async {
        let around = SomePlaces(holding: [flore], access: .undecided)

        let suggestions = PlaceSuggestions(from: around)
        await suggestions.look()

        #expect(suggestions.state == .nothingToOffer)
        #expect(suggestions.couldLookFurther == .theDevicesLocation)
        #expect(around.timesRead == 0, "where the device is was read before anybody was asked")
        #expect(around.timesAsked == 0, "opening the widget asked for the location permission")
    }

    @Test("being allowed to look offers what is around")
    func allowedToLook() async {
        let around = SomePlaces(holding: [flore], access: .undecided, answering: .allowed)
        let suggestions = PlaceSuggestions(from: around)
        await suggestions.look()

        await suggestions.askToLook()

        #expect(around.timesAsked == 1)
        #expect(suggestions.state == .offering([flore]))
    }

    // The acceptance criterion, and the whole of what a refusal costs: no
    // offer, no notice, and a widget that is answered by typing the place
    // instead — which is what the sheet is made of either way.
    @Test("a refusal offers nothing and says nothing about it")
    func aRefusal() async {
        let around = SomePlaces(holding: [flore], access: .undecided, answering: .refused)
        let suggestions = PlaceSuggestions(from: around)
        await suggestions.look()

        await suggestions.askToLook()

        #expect(suggestions.state == .nothingToOffer)
        #expect(suggestions.couldLookFurther == nil, "the refusal was offered again")
        #expect(around.timesRead == 0, "a refused device was read anyway")
    }

    // Somebody who said no once is not asked again the next time they tap a
    // widget: the way back from a refusal is Settings, and an offer that came
    // back every time would be the app asking for ever.
    @Test("a device already refused is never offered again")
    func alreadyRefused() async {
        let around = SomePlaces(holding: [flore], access: .refused)

        let suggestions = PlaceSuggestions(from: around)
        await suggestions.look()

        #expect(suggestions.state == .nothingToOffer)
        #expect(suggestions.couldLookFurther == nil)
        #expect(around.timesAsked == 0)
        #expect(around.timesRead == 0)
    }

    // MARK: - While the device is being asked

    // Finding a place takes a moment — a fix, then a lookup — and a sheet that
    // showed nothing for that moment would read as a device that had already
    // answered "nowhere".
    @Test("the looking is visible while it happens")
    func whileLooking() async {
        let around = SomePlaces(holding: [flore])
        around.holdsItsAnswer = true
        let suggestions = PlaceSuggestions(from: around)

        let looking = Task { await suggestions.look() }
        while around.timesRead == 0 { await Task.yield() }
        #expect(suggestions.state == .looking)

        around.answerNow()
        await looking.value
        #expect(suggestions.state == .offering([flore]))
    }

    // MARK: - What goes in the file

    // Plain place text and nothing around it: the token's characters are
    // replaced by the words a place is called, so the line reads afterwards as
    // a line somebody wrote (ADR 0001).
    @Test("what a place writes is what it is called")
    func whatAPlaceWrites() {
        #expect(flore.written == "Café de Flore")
        #expect(Place(id: "paris", name: "Paris").written == "Paris")
    }

    // The region tells two places of the same name apart in the picker; it is
    // not what somebody writes in the middle of their own sentence.
    @Test("the region is for telling places apart, not for the entry")
    func theRegionStaysOutOfTheEntry() {
        let here = Place(id: "a", name: "Starbucks", region: "Rue de Rivoli, Paris")
        #expect(here.written == "Starbucks")
    }
}

/// Somewhere the device is, said rather than found.
///
/// A class, and unchecked, because being asked has to stick and because the
/// answer is held back on purpose in one of the tests above.
final class SomePlaces: Places, @unchecked Sendable {
    private let around: Surroundings
    private let whenAsked: PlaceAccess
    private let named: [Coordinate: Place]
    private let lock = NSLock()
    private var standing: PlaceAccess
    private var asked = 0
    private var read = 0
    private var lookedUp: [Coordinate] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Whether a reading waits to be let go, for a test about what is on
    /// screen while the device is being asked.
    var holdsItsAnswer = false

    init(
        holding around: [Place],
        naming named: [Coordinate: Place] = [:],
        access: PlaceAccess = .allowed,
        answering: PlaceAccess = .allowed
    ) {
        self.named = named
        // Named places, all of them within reach — the order they were given
        // in is the order they are offered in, which is what these tests are
        // about. Which of them *leads* is `SurroundingsTests`.
        self.around = Surroundings(
            named: around.map { NearbyPlace(place: $0, metresAway: 0) }
        )
        self.standing = access
        self.whenAsked = answering
    }

    var access: PlaceAccess { lock.withLock { standing } }

    var timesAsked: Int { lock.withLock { asked } }

    var timesRead: Int { lock.withLock { read } }

    /// Every position a name was asked for, which is what the bounded-lookup
    /// tests count.
    var positionsLookedUp: [Coordinate] { lock.withLock { lookedUp } }

    func ask() async -> PlaceAccess {
        lock.withLock {
            asked += 1
            if standing == .undecided { standing = whenAsked }
            return standing
        }
    }

    func around() async -> Surroundings {
        lock.withLock { read += 1 }
        if holdsItsAnswer {
            await withCheckedContinuation { continuation in
                lock.withLock { waiting.append(continuation) }
            }
        }
        return around
    }

    /// The place at a position, from what the test said stands there.
    ///
    /// Deliberately answers whatever the permission says, like the real one:
    /// naming a coordinate the library handed over is a question about the
    /// map, not about where this device is.
    func place(at position: Coordinate) async -> Place? {
        lock.withLock { lookedUp.append(position) }
        // The nearest seeded place within a stone's throw, so that a test can
        // say where a café is without having to know which way a stop's centre
        // rounded.
        return
            named
            .map { (at: $0.key, place: $0.value) }
            .filter { $0.at.metres(to: position) <= 200 }
            .min { $0.at.metres(to: position) < $1.at.metres(to: position) }?
            .place
    }

    /// Lets go of every reading that is being held.
    func answerNow() {
        holdsItsAnswer = false
        let held = lock.withLock {
            let held = waiting
            waiting = []
            return held
        }
        held.forEach { $0.resume() }
    }
}
