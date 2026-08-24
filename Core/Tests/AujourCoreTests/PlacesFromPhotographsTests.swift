import Foundation
import Testing

@testable import AujourCore

// The {{location}} widget is about the Journal Day rather than about now, and
// this is where that is decided: which of the day's photographs it reads, what
// the places worked out from them cost, which of them leads the offer, and
// what happens when one of the two permissions behind it is refused. All of it
// over a library and a map that are said rather than read.

@MainActor
@Suite("The places a day's photographs put a location widget on")
struct PlacesFromPhotographsTests {
    private let monday = JournalDay(year: 2026, month: 3, day: 9)

    private let flore = Coordinate(latitude: 48.85419, longitude: 2.33262)
    private let orsay = Coordinate(latitude: 48.85995, longitude: 2.32660)

    /// Friday, long after Monday is over — a day being written up later.
    private var friday: Date { instant(2026, 3, 13, 18, 0, in: paris) }

    /// Monday afternoon, while Monday is still being lived.
    private var mondayAfternoon: Date { instant(2026, 3, 9, 16, 0, in: paris) }

    // MARK: - The day's own places

    // The acceptance criterion: the widget offers places worked out from the
    // photographs taken on the day, and what confirming one writes is the
    // plain text a nearby place writes.
    @Test("the places the day was photographed in are offered")
    func theDaysOwnPlaces() async {
        let suggestions = await looked(at: [photograph(at: flore, 11, 4)])

        #expect(suggestions.offered?.name == "Café de Flore")
        #expect(suggestions.offered?.written == "Café de Flore, 11:04")
    }

    // The other half of it, and the reason the hour is worth carrying: a
    // photograph knows when it was taken and a fix taken on Friday does not.
    @Test("a photographed place carries the hour the day got there")
    func theHourItWasTaken() async {
        let suggestions = await looked(at: [
            photograph(at: flore, 13, 30), photograph(at: flore, 11, 4),
        ])

        #expect(suggestions.offered?.atTime == "11:04")
    }

    // The whole point of the issue. A Monday written up on Friday is offered
    // Monday's places, and Friday's street is behind them rather than in front
    // — confidently offered and one tap from being confirmed as where somebody
    // was on Monday.
    @Test("a day filled in later is offered that day's places, ahead of the live fix")
    func aDayFilledInLater() async {
        let map = SomePlaces(
            holding: [Place(id: "friday", name: "Rue de Rivoli")],
            naming: [flore: Place(id: "flore", name: "Café de Flore")]
        )
        let suggestions = suggestions(from: map, holding: [photograph(at: flore, 11, 4)], at: friday)

        await suggestions.look()

        #expect(suggestions.state == .offering([
            Place(id: "photographed:flore@1773050640.0", name: "Café de Flore", atTime: "11:04"),
            Place(id: "friday", name: "Rue de Rivoli"),
        ]))
    }

    // Only *that day's*. The library is asked for the Journal Day's own
    // midnight-to-midnight stretch, so Friday's photographs are Friday's
    // business however recently they were taken.
    @Test("the photographs read are the day's, not the ones taken since")
    func onlyThatDaysPhotographs() async {
        let library = ALibraryWithPositions(holding: [
            photograph(at: flore, 11, 4),
            DayPhotograph(
                id: "friday", takenAt: instant(2026, 3, 13, 12, 0, in: paris), position: orsay
            ),
        ])
        let map = SomePlaces(
            holding: [],
            naming: [flore: Place(id: "flore", name: "Café de Flore"), orsay: Place(id: "orsay", name: "Musée d'Orsay")]
        )
        let suggestions = PlaceSuggestions(
            from: map, photographsFrom: library, for: monday,
            at: friday, in: paris, locale: Locale(identifier: "en_GB")
        )

        await suggestions.look()

        #expect(suggestions.state == .offering([
            Place(id: "photographed:flore@1773050640.0", name: "Café de Flore", atTime: "11:04")
        ]))
    }

    // A day still being lived is a day whose live fix is as good as its
    // photographs, so the fix leads and the day's places fall in behind it.
    @Test("a day still being lived leads with the live fix")
    func theDayStillBeingLived() async {
        let map = SomePlaces(
            holding: [Place(id: "here", name: "Jardin du Luxembourg")],
            naming: [flore: Place(id: "flore", name: "Café de Flore")]
        )
        let suggestions = suggestions(
            from: map, holding: [photograph(at: flore, 11, 4)], at: mondayAfternoon
        )

        await suggestions.look()

        #expect(suggestions.offered?.name == "Jardin du Luxembourg")
        #expect(suggestions.places.count == 2)
    }

    // Somebody still sitting where they were photographed would otherwise be
    // offered the same café twice over, once with an hour on it and once
    // without.
    @Test("a place found both ways is offered once")
    func onceRatherThanTwice() async {
        let map = SomePlaces(
            holding: [Place(id: "here", name: "Café de Flore")],
            naming: [flore: Place(id: "flore", name: "Café de Flore")]
        )
        let suggestions = suggestions(
            from: map, holding: [photograph(at: flore, 11, 4)], at: mondayAfternoon
        )

        await suggestions.look()

        #expect(suggestions.places.map(\.written) == ["Café de Flore"])
    }

    // A day spent wandering one neighbourhood makes stops that are genuinely
    // apart on the ground and all come back named after the neighbourhood,
    // because that is what is there. One word four times over is not a picker.
    @Test("stops that come back with the same name are offered once")
    func onlyOneNeighbourhood() async {
        let wandering = (0..<4).map {
            DayPhotograph(
                id: "\($0)",
                takenAt: instant(2026, 3, 9, 10 + $0, 0, in: paris),
                position: Coordinate(latitude: 48.85 + Double($0) / 500, longitude: 2.33)
            )
        }
        // Everywhere in the quarter is the quarter.
        let quarter = SomePlaces(
            holding: [],
            naming: Dictionary(
                uniqueKeysWithValues: wandering.compactMap { photograph in
                    photograph.position.map {
                        ($0, Place(id: "quarter", name: "Saint-Germain-des-Prés"))
                    }
                }
            )
        )

        let suggestions = suggestions(from: quarter, holding: wandering, at: friday)
        await suggestions.look()

        #expect(quarter.positionsLookedUp.count == 4, "the stops were not four to begin with")
        #expect(suggestions.places.map(\.written) == ["Saint-Germain-des-Prés, 10:00"])
    }

    // MARK: - What the naming costs

    // The acceptance criterion, and the reason the gathering happens before
    // anything is named rather than after: fifty pictures of one lunch is one
    // lookup, not fifty.
    @Test("a day of photographs from one place costs one lookup")
    func oneSpotIsOneLookup() async {
        let lunch = (0..<50).map { photograph(at: flore, 12, $0 % 60) }
        let map = SomePlaces(holding: [], naming: [flore: Place(id: "flore", name: "Café de Flore")])

        let suggestions = suggestions(from: map, holding: lunch, at: friday)
        await suggestions.look()

        #expect(map.positionsLookedUp.count == 1)
        #expect(suggestions.places.count == 1)
    }

    // And a day that went everywhere is capped rather than unbounded: a sheet
    // is in front of somebody with a sentence waiting.
    @Test("a day of photographs from everywhere costs a bounded number of lookups")
    func everywhereIsStillBounded() async {
        // Two hundred photographs, each a kilometre from the last — two
        // hundred stops, if nothing capped them.
        let allOverParis = (0..<200).map {
            DayPhotograph(
                id: "\($0)",
                takenAt: instant(2026, 3, 9, 8, 0, in: paris).addingTimeInterval(Double($0) * 60),
                position: Coordinate(latitude: 48.85 + Double($0) / 100, longitude: 2.33)
            )
        }
        let map = SomePlaces(holding: [])

        let suggestions = suggestions(from: map, holding: allOverParis, at: friday)
        await suggestions.look()

        #expect(map.positionsLookedUp.count <= PlaceSuggestions.asManyStopsAsAreWorthNaming)
    }

    // Where the day was spent is where most of its pictures were taken; a
    // single frame through a train window is what gives way when there are
    // more stops than lookups to spend.
    @Test("the stops worth naming are the ones the day was spent at")
    func theStopsWorthNaming() async {
        let spread = (0..<6).enumerated().flatMap { at, _ in
            // The later a stop, the more photographs it holds — so the first
            // two are the ones dropped, and the order is not what saved them.
            (0...at).map { picture in
                DayPhotograph(
                    id: "\(at)-\(picture)",
                    takenAt: instant(2026, 3, 9, 8 + at, picture, in: paris),
                    position: Coordinate(latitude: 48.85 + Double(at) / 100, longitude: 2.33)
                )
            }
        }
        let map = SomePlaces(holding: [])

        let suggestions = suggestions(from: map, holding: spread, at: friday)
        await suggestions.look()

        // Sorted, because *which* stops were named is the claim here and the
        // lookups are deliberately made at once — what order they come back in
        // is the map server's business. That the offer is put back into the
        // order the day happened in is `theDaysOwnPlaces` and the two
        // ordering tests above.
        let named = map.positionsLookedUp.map { ($0.latitude * 100).rounded() / 100 }.sorted()
        #expect(named == [48.87, 48.88, 48.89, 48.9], "the busiest stops were not the ones named")
    }

    // The lookups are made at once, so they come back in whatever order the
    // map server felt like — and the day still has to read forward. Said with
    // a map that answers the morning's café last, which is the case a test
    // over an instant map would never see.
    @Test("the day's places read forward however the lookups came back")
    func forwardWhicheverAnsweredFirst() async {
        let map = AMapThatAnswersBackwards(
            naming: [flore: "Café de Flore", orsay: "Musée d'Orsay"]
        )
        let suggestions = PlaceSuggestions(
            from: map,
            photographsFrom: ALibraryWithPositions(holding: [
                photograph(at: flore, 11, 4), photograph(at: orsay, 15, 30),
            ]),
            for: monday, at: friday, in: paris, locale: Locale(identifier: "en_GB")
        )

        await suggestions.look()

        #expect(suggestions.places.map(\.written) == ["Café de Flore, 11:04", "Musée d'Orsay, 15:30"])
    }

    // MARK: - Falling back on the live fix

    @Test("a day with no photographs falls back on the live fix")
    func noPhotographs() async {
        let map = SomePlaces(holding: [Place(id: "here", name: "Rue de Rivoli")])

        let suggestions = suggestions(from: map, holding: [], at: friday)
        await suggestions.look()

        #expect(suggestions.offered?.name == "Rue de Rivoli")
        #expect(map.positionsLookedUp.isEmpty, "a name was looked up for a day with no positions")
    }

    @Test("a day whose photographs carry no position falls back on the live fix")
    func noPositions() async {
        let map = SomePlaces(holding: [Place(id: "here", name: "Rue de Rivoli")])
        let unplaced = [DayPhotograph(id: "a", takenAt: instant(2026, 3, 9, 11, 0, in: paris))]

        let suggestions = suggestions(from: map, holding: unplaced, at: friday)
        await suggestions.look()

        #expect(suggestions.offered?.name == "Rue de Rivoli")
        #expect(map.positionsLookedUp.isEmpty)
    }

    @Test("a refused library falls back on the live fix, and is not read")
    func aRefusedLibrary() async {
        let map = SomePlaces(holding: [Place(id: "here", name: "Rue de Rivoli")])
        let library = ALibraryWithPositions(holding: [photograph(at: flore, 11, 4)], access: .refused)

        let suggestions = PlaceSuggestions(
            from: map, photographsFrom: library, for: monday,
            at: friday, in: paris, locale: Locale(identifier: "en_GB")
        )
        await suggestions.look()

        #expect(suggestions.offered?.name == "Rue de Rivoli")
        #expect(library.timesRead == 0, "a refused library was read anyway")
    }

    // The other half of riding two permissions: refusing where the device is
    // does not refuse where the day's own pictures say it was, and naming one
    // of those is a question about the map rather than about this device.
    @Test("a refused device is still offered the places its photographs were taken")
    func aRefusedDevice() async {
        let map = SomePlaces(
            holding: [Place(id: "here", name: "Rue de Rivoli")],
            naming: [flore: Place(id: "flore", name: "Café de Flore")],
            access: .refused
        )

        let suggestions = suggestions(from: map, holding: [photograph(at: flore, 11, 4)], at: friday)
        await suggestions.look()

        #expect(suggestions.places.map(\.name) == ["Café de Flore"])
        #expect(map.timesRead == 0, "a refused device was read anyway")
    }

    // Neither one: nothing on offer, nothing said about it, and a sheet that
    // is still answered by typing the place.
    @Test("a widget with neither offers nothing and says nothing about it")
    func neitherOfThem() async {
        let map = SomePlaces(holding: [], access: .refused)
        let library = ALibraryWithPositions(
            holding: [photograph(at: flore, 11, 4)], access: .refused
        )

        let suggestions = PlaceSuggestions(
            from: map, photographsFrom: library, for: monday, at: friday, in: paris
        )
        await suggestions.look()

        #expect(suggestions.state == .nothingToOffer)
        #expect(suggestions.couldLookFurther == nil)
    }

    // MARK: - What is left to ask about

    // Nothing to tap while it is being read: a finger landing on the offer
    // mid-read would set a second reading going behind the first, and which of
    // the two landed last would decide what the sheet ended up showing.
    @Test("nothing is offered to be tapped while the reading is happening")
    func nothingToTapWhileLooking() async {
        let map = SomePlaces(holding: [Place(id: "here", name: "Rue de Rivoli")])
        map.holdsItsAnswer = true
        let suggestions = PlaceSuggestions(
            from: map,
            photographsFrom: ALibraryWithPositions(holding: [], access: .undecided),
            for: monday, at: friday, in: paris
        )

        let looking = Task { await suggestions.look() }
        while map.timesRead == 0 { await Task.yield() }
        #expect(suggestions.state == .looking)
        #expect(suggestions.couldLookFurther == nil, "the offer could be tapped mid-read")

        map.answerNow()
        await looking.value
        #expect(suggestions.couldLookFurther == .theDaysPhotographs)
    }

    @Test("both permissions undecided is one offer to look, naming both")
    func bothUndecided() async {
        let suggestions = PlaceSuggestions(
            from: SomePlaces(holding: [], access: .undecided),
            photographsFrom: ALibraryWithPositions(holding: [], access: .undecided),
            for: monday, at: friday, in: paris
        )

        await suggestions.look()

        #expect(suggestions.couldLookFurther == .both)
    }

    // The case the issue is really about: somebody who granted the location
    // permission back when the widget only knew how to ask for that must still
    // be offered the better answer.
    @Test("a device already allowed still offers to look at the day's photographs")
    func onlyTheLibraryLeft() async {
        let map = SomePlaces(holding: [Place(id: "here", name: "Rue de Rivoli")])
        let library = ALibraryWithPositions(holding: [], access: .undecided)

        let suggestions = PlaceSuggestions(
            from: map, photographsFrom: library, for: monday, at: friday, in: paris
        )
        await suggestions.look()

        #expect(suggestions.state == .offering([Place(id: "here", name: "Rue de Rivoli")]))
        #expect(suggestions.couldLookFurther == .theDaysPhotographs)
    }

    @Test("saying yes to the library offers the day's places")
    func sayingYesToTheLibrary() async {
        let map = SomePlaces(
            holding: [], naming: [flore: Place(id: "flore", name: "Café de Flore")]
        )
        let library = ALibraryWithPositions(
            holding: [photograph(at: flore, 11, 4)], access: .undecided, answering: .allowed
        )
        let suggestions = PlaceSuggestions(
            from: map, photographsFrom: library, for: monday,
            at: friday, in: paris, locale: Locale(identifier: "en_GB")
        )
        await suggestions.look()

        await suggestions.askToLook()

        #expect(suggestions.offered?.written == "Café de Flore, 11:04")
        #expect(suggestions.couldLookFurther == nil)
    }

    @Test("saying no to the library offers nothing and says nothing about it")
    func sayingNoToTheLibrary() async {
        let map = SomePlaces(holding: [], access: .refused)
        let library = ALibraryWithPositions(
            holding: [photograph(at: flore, 11, 4)], access: .undecided, answering: .refused
        )
        let suggestions = PlaceSuggestions(
            from: map, photographsFrom: library, for: monday, at: friday, in: paris
        )
        await suggestions.look()

        await suggestions.askToLook()

        #expect(suggestions.state == .nothingToOffer)
        #expect(suggestions.couldLookFurther == nil)
    }

    // A sheet with no day behind it — a preview, and every test of something
    // else — has no photographs to read and never offers to ask for them.
    @Test("no day behind the sheet is the live fix and nothing else")
    func noDayAtAll() async {
        let map = SomePlaces(holding: [Place(id: "here", name: "Rue de Rivoli")])
        let library = ALibraryWithPositions(holding: [], access: .undecided)

        let suggestions = PlaceSuggestions(from: map, photographsFrom: library)
        await suggestions.look()

        #expect(suggestions.couldLookFurther == nil)
        #expect(library.timesRead == 0)
    }

    // MARK: - Saying it

    private func photograph(at position: Coordinate, _ hour: Int, _ minute: Int) -> DayPhotograph {
        DayPhotograph(
            id: "\(hour):\(minute)",
            takenAt: instant(2026, 3, 9, hour, minute, in: paris),
            position: position
        )
    }

    private func suggestions(
        from map: SomePlaces, holding photographs: [DayPhotograph], at now: Date
    ) -> PlaceSuggestions {
        PlaceSuggestions(
            from: map,
            photographsFrom: ALibraryWithPositions(holding: photographs),
            for: monday,
            at: now,
            in: paris,
            locale: Locale(identifier: "en_GB")
        )
    }

    /// One look, over a map that names the two places these tests use.
    private func looked(at photographs: [DayPhotograph]) async -> PlaceSuggestions {
        let map = SomePlaces(
            holding: [],
            naming: [
                flore: Place(id: "flore", name: "Café de Flore", region: "Saint-Germain"),
                orsay: Place(id: "orsay", name: "Musée d'Orsay"),
            ]
        )
        let suggestions = suggestions(from: map, holding: photographs, at: friday)
        await suggestions.look()
        return suggestions
    }
}

extension PlaceSuggestions {
    /// The places on offer, for a test that is about which they are rather
    /// than about the state around them.
    fileprivate var places: [Place] {
        guard case .offering(let places) = state else { return [] }
        return places
    }
}

/// A map that takes longer over the places a day reached first.
///
/// The one thing an instant fake cannot show: the lookups are made at once, so
/// nothing may depend on which of them answers first.
private struct AMapThatAnswersBackwards: Places {
    let naming: [Coordinate: String]

    let access = PlaceAccess.allowed

    func ask() async -> PlaceAccess { .allowed }

    func around() async -> Surroundings { Surroundings() }

    func place(at position: Coordinate) async -> Place? {
        // The southern one takes a moment and the northern one is instant —
        // and these tests' morning café is the southern one, so the day's
        // first place is the last to be named.
        if position.latitude < 48.857 { try? await Task.sleep(for: .milliseconds(100)) }
        guard let name = naming[position] else { return nil }
        return Place(id: name, name: name)
    }
}

/// A day's photographs, said rather than read — and the positions they carry,
/// which is what these tests are about.
///
/// A class, and unchecked, because being asked has to stick and because the
/// tests count what was read.
private final class ALibraryWithPositions: PhotoLibrary, @unchecked Sendable {
    private let holding: [DayPhotograph]
    private let whenAsked: PhotoLibraryAccess
    private let lock = NSLock()
    private var standing: PhotoLibraryAccess
    private var read = 0

    init(
        holding: [DayPhotograph],
        access: PhotoLibraryAccess = .allowed,
        answering: PhotoLibraryAccess = .allowed
    ) {
        self.holding = holding
        self.standing = access
        self.whenAsked = answering
    }

    var access: PhotoLibraryAccess { lock.withLock { standing } }

    var timesRead: Int { lock.withLock { read } }

    func ask() async -> PhotoLibraryAccess {
        lock.withLock {
            if standing == .undecided { standing = whenAsked }
            return standing
        }
    }

    func photographs(during span: DateInterval) async -> [DayPhotograph] {
        guard access == .allowed else { return [] }
        lock.withLock { read += 1 }
        return holding.filter { $0.takenAt >= span.start && $0.takenAt < span.end }
    }

    func thumbnail(of photograph: DayPhotograph) async -> Data? { nil }

    func contents(of photograph: DayPhotograph) async -> Data? { nil }
}
