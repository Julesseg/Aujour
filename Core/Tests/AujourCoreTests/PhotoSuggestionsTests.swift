import Foundation
import Testing

@testable import AujourCore

// What the suggestions panel has to get right is which photographs belong to
// the day on screen, and when it should not be there at all. Both are decided
// here, over a library said rather than read — the pixels and the permission
// alert are the app's, and neither is a thing this module has ever seen.

@MainActor
@Suite("The photographs a day is offered")
struct PhotoSuggestionsTests {
    // MARK: - What is offered

    @Test("a day's photographs are offered in the order the day took them")
    func theDaysPhotographs() async {
        let morning = DayPhotograph(id: "morning", takenAt: instant(2026, 3, 14, 8, in: paris))
        let evening = DayPhotograph(id: "evening", takenAt: instant(2026, 3, 14, 19, in: paris))
        let library = ALibrary(holding: [evening, morning])

        let suggestions = PhotoSuggestions(from: library, in: paris)
        await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 14))

        #expect(suggestions.state == .offering([morning, evening]))
    }

    @Test("a day the library has nothing from has no panel")
    func aDayWithNoPhotographs() async {
        let library = ALibrary(holding: [])

        let suggestions = PhotoSuggestions(from: library, in: paris)
        await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 14))

        #expect(suggestions.state == .nothingToOffer)
    }

    // The whole of the backfill criterion: the day being written about decides
    // which photographs are offered, and a day filled in a week later is
    // offered its own.
    @Test("a day filled in later is offered that day's photographs and not today's")
    func aBackfilledDay() async {
        let onTheDay = DayPhotograph(id: "market", takenAt: instant(2026, 3, 14, 11, in: paris))
        let today = DayPhotograph(id: "today", takenAt: instant(2026, 3, 21, 11, in: paris))
        let library = ALibrary(holding: [onTheDay, today])
        let suggestions = PhotoSuggestions(from: library, in: paris)

        await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 14))
        #expect(suggestions.state == .offering([onTheDay]))

        await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 21))
        #expect(suggestions.state == .offering([today]))
    }

    // Midnight to midnight where the device is, which is the same stretch the
    // day's meetings are read for (`JournalDay.span(in:)`) and the same one the
    // user's own photos app draws the day as.
    @Test("the day is its own midnight to midnight, wherever the device is")
    func theStretchAsked() async {
        let library = ALibrary(holding: [])
        let suggestions = PhotoSuggestions(from: library, in: paris)

        await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 14))

        #expect(
            library.read == [
                DateInterval(
                    start: instant(2026, 3, 14, 0, in: paris),
                    end: instant(2026, 3, 15, 0, in: paris)
                )
            ]
        )
    }

    // MARK: - The permission, which is the panel's alone

    // Nothing is asked for by a day being opened. The panel says there is
    // something to look at, and asking happens when the user says to look —
    // which is what keeps the library permission a thing Aujour asks about
    // suggestions and about nothing else.
    @Test("a library nobody has been asked about is offered to look in, not read")
    func aLibraryNobodyHasBeenAskedAbout() async {
        let library = ALibrary(
            holding: [DayPhotograph(id: "market", takenAt: instant(2026, 3, 14, 11, in: paris))],
            access: .undecided
        )

        let suggestions = PhotoSuggestions(from: library, in: paris)
        await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 14))

        #expect(suggestions.state == .couldLook)
        #expect(library.read.isEmpty, "the library was read before anybody was asked")
        #expect(library.timesAsked == 0, "a day being opened asked for the library")
    }

    @Test("being allowed to look shows the day's photographs")
    func allowedToLook() async {
        let market = DayPhotograph(id: "market", takenAt: instant(2026, 3, 14, 11, in: paris))
        let library = ALibrary(holding: [market], access: .undecided, answering: .allowed)
        let suggestions = PhotoSuggestions(from: library, in: paris)
        await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 14))

        await suggestions.askToLook()

        #expect(library.timesAsked == 1)
        #expect(suggestions.state == .offering([market]))
    }

    // The acceptance criterion, and the whole of what a refusal costs: no
    // panel, no notice, and a photo button on the row that works exactly as it
    // did — the picker needs no permission at all.
    @Test("a refusal leaves no panel and nothing said about it")
    func aRefusal() async {
        let library = ALibrary(
            holding: [DayPhotograph(id: "market", takenAt: instant(2026, 3, 14, 11, in: paris))],
            access: .undecided,
            answering: .refused
        )
        let suggestions = PhotoSuggestions(from: library, in: paris)
        await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 14))

        await suggestions.askToLook()

        #expect(suggestions.state == .nothingToOffer)
        #expect(library.read.isEmpty, "a refused library was read anyway")
    }

    // Somebody who said no once is not asked again on the next day they open:
    // the way back from a refusal is Settings, and a panel that re-offered
    // itself every morning would be the app asking for ever.
    @Test("a library already refused is never offered again")
    func aLibraryAlreadyRefused() async {
        let library = ALibrary(holding: [], access: .refused)

        let suggestions = PhotoSuggestions(from: library, in: paris)
        await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 14))

        #expect(suggestions.state == .nothingToOffer)
        #expect(library.timesAsked == 0)
    }

    // MARK: - The day changing underneath

    // A day is opened, and another is opened before the library has answered
    // about the first — the calendar, or an app left open overnight moving on.
    // The answer that arrives is about a day nobody is looking at.
    @Test("an answer about a day that has gone is not put on screen")
    func anAnswerAboutADayThatHasGone() async {
        let march = DayPhotograph(id: "march", takenAt: instant(2026, 3, 14, 11, in: paris))
        let april = DayPhotograph(id: "april", takenAt: instant(2026, 4, 2, 11, in: paris))
        let library = ALibrary(holding: [march, april])

        let suggestions = PhotoSuggestions(from: library, in: paris)
        library.holdsItsAnswer = true
        let theDayLeftBehind = Task { await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 14)) }
        while library.read.isEmpty { await Task.yield() }

        library.holdsItsAnswer = false
        await suggestions.look(for: JournalDay(year: 2026, month: 4, day: 2))
        library.answerNow()
        await theDayLeftBehind.value

        #expect(suggestions.state == .offering([april]))
    }

    // MARK: - No library at all

    // A preview, and a test of something else. Nothing to offer, and nothing
    // asked for.
    @Test("suggestions with no library behind them offer nothing")
    func noLibraryAtAll() async {
        let suggestions = PhotoSuggestions()

        await suggestions.look(for: JournalDay(year: 2026, month: 3, day: 14))
        await suggestions.askToLook()

        #expect(suggestions.state == .nothingToOffer)
    }
}

/// A photo library said rather than read: what it holds, what it will say when
/// it is asked, and — for the one test that needs it — a read it does not
/// answer yet.
///
/// Unchecked because a test drives it from the main actor and nowhere else,
/// while the seam it stands in for is one the app reaches from anywhere.
private final class ALibrary: PhotoLibrary, @unchecked Sendable {
    private let holding: [DayPhotograph]
    private var permission: PhotoLibraryAccess
    private let answering: PhotoLibraryAccess

    /// The stretches this has been asked about, in the order they were asked.
    private(set) var read: [DateInterval] = []
    private(set) var timesAsked = 0

    /// Set to leave the next read unanswered, so that the day can change while
    /// one is in flight.
    var holdsItsAnswer = false
    private var held: [CheckedContinuation<Void, Never>] = []

    init(
        holding: [DayPhotograph],
        access: PhotoLibraryAccess = .allowed,
        answering: PhotoLibraryAccess = .allowed
    ) {
        self.holding = holding
        self.permission = access
        self.answering = answering
    }

    func answerNow() {
        let waiting = held
        held = []
        for answer in waiting { answer.resume() }
    }

    var access: PhotoLibraryAccess { permission }

    func ask() async -> PhotoLibraryAccess {
        timesAsked += 1
        permission = answering
        return permission
    }

    func photographs(during span: DateInterval) async -> [DayPhotograph] {
        read.append(span)
        if holdsItsAnswer {
            await withCheckedContinuation { held.append($0) }
        }
        // Half open, as the day's own stretch is and as the library reads it:
        // the first instant of the next day is not this day's.
        return holding.filter { $0.takenAt >= span.start && $0.takenAt < span.end }
    }

    func thumbnail(of photograph: DayPhotograph) async -> Data? { nil }
    func contents(of photograph: DayPhotograph) async -> Data? { nil }
}
