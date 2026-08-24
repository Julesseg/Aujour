import Foundation
import Observation

/// A run of places offered together, and where they were found.
///
/// The two answers stay apart all the way to the screen rather than being
/// merged into one list, because where a place came from is something the user
/// should be able to see. "Near you" and "From photos" are different kinds of
/// claim — one is about this minute and the other about the day being written
/// — and a picker that ran them together would be asking somebody to trust
/// both equally.
public struct SuggestedPlaces: Hashable, Sendable, Identifiable {
    /// Which of the two ways of answering "where were you" this run came from.
    public enum Source: Hashable, Sendable {
        /// What the device names around itself, now.
        case nearby

        /// What the day's own photographs say, worked out from the positions
        /// they carry.
        case theDaysPhotographs
    }

    public let from: Source

    /// Never empty — a run with nothing in it is dropped rather than offered.
    public let places: [Place]

    /// One run per source, which is what makes a run a section on screen.
    public var id: Source { from }

    public init(from: Source, places: [Place]) {
        self.from = from
        self.places = places
    }
}

/// What a `{{location}}` widget offers the user: the places the day's own
/// photographs were taken, where the device says they are now, and the rest to
/// choose instead.
///
/// A day is written up in the evening, or a week later, and the phone that was
/// there is the one being written on — so the widget offers the place rather
/// than asking somebody to spell it. Which places those are is the only
/// question here, and it has two answers that are read at once:
///
/// - **Where the day was photographed.** The positions the day's own pictures
///   carry, gathered into ``PhotographedStop``s and named one apiece. These
///   are facts about the day being written *about*.
/// - **Where the device is now.** Whatever it names around itself, in the
///   order it named them — a fact about the moment the sheet was opened.
///
/// ## Which of them leads, and why it is the whole point
///
/// A day still running is a day whose live fix is as good as its photographs,
/// and it leads. A day that is over is not: a Monday written up on Friday
/// would otherwise be offered Friday's street, confidently and one tap from
/// being confirmed into somebody's journal as where they were on Monday. The
/// photographs from that Monday already know better, so for any day but the
/// one being lived they go first and the live fix falls in behind them.
///
/// That is the same principle ``Surroundings/toOffer`` is made of, applied one
/// level up: a wrong answer somebody would confirm with one tap is the one
/// thing this must never do. There the safe answer is the town; here it is the
/// day's own photographs, and recency is what tells the two apart.
///
/// ## Two permissions, either of which is enough
///
/// The offer rides the photo library as well as the device's location, and
/// neither is required. Somebody who refused the one and granted the other is
/// still offered places — from their pictures, or from the fix — because these
/// are two different ways of answering the same question and refusing one of
/// them is not refusing the question.
///
/// It holds no map and no permission alert. Both are the app's, behind
/// ``Places`` and ``PhotoLibrary`` — which is what lets every rule here be
/// unit-tested on Linux against places that are said rather than found.
///
/// ## Nothing on offer is the ordinary case
///
/// A refused device, a refused library, a day the camera missed, photographs
/// that carry no position, and somewhere with no place worth naming all come
/// out the same: no offer at all. None of them is a failure and none of them
/// is said out loud, because the sheet is answerable either way — the place is
/// typed, which is what answering a placeholder was before there was a device
/// to ask.
@MainActor
@Observable
public final class PlaceSuggestions {
    /// What the sheet should be showing above the field the place is typed in.
    ///
    /// Only ever about the places themselves. Whether there is still a
    /// permission worth offering to ask for is ``couldLookFurther``, and it is
    /// deliberately a second thing: there are two permissions behind this and
    /// one of them can be answered while the other is still worth offering, so
    /// "here are some places, and there are more to be had" is a real state of
    /// the world that no single case could say.
    public enum State: Hashable, Sendable {
        /// No offer. Nothing allowed, nothing found, or nothing to find.
        case nothingToOffer

        /// The device or the library is being read. On screen while it is,
        /// because finding a place is a fix and then a lookup, and a sheet
        /// that showed nothing meanwhile would read as a device that had
        /// answered "nowhere".
        case looking

        /// The places to offer, kept in the runs they were found in and in
        /// the order those runs are worth offering in. The very first place
        /// of the very first run is the offer itself.
        ///
        /// A run with nothing in it is never here, so a day with no
        /// photographs is one run rather than one run and an empty one.
        case offering([SuggestedPlaces])
    }

    /// What there is still worth offering to go and look at — a permission
    /// nobody has been asked for that would add places to the offer.
    ///
    /// Named rather than a `Bool` because the sheet has to say what it is
    /// about to ask for. Somebody who taps a `{{location}}` widget and is
    /// shown a photo-library alert with no warning has been ambushed, however
    /// good the reason.
    public enum ToLookFurther: Hashable, Sendable {
        /// Where the device is now.
        case theDevicesLocation

        /// Where the day's own photographs were taken.
        case theDaysPhotographs

        /// Both, which is one tap and two alerts in a row.
        case both
    }

    public private(set) var state: State = .nothingToOffer

    /// `nil` once there is nothing left to ask about — everything already
    /// granted, already refused, or not there to ask about at all.
    public private(set) var couldLookFurther: ToLookFurther?

    /// The device, or none at all — which is a preview, and a test of
    /// something else, and offers nothing.
    @ObservationIgnored private let places: (any Places)?

    /// The library the day's photographs are read from, or none.
    @ObservationIgnored private let library: (any PhotoLibrary)?

    /// The day being written about, or none — a sheet with no day behind it
    /// has no photographs to read and is the live fix alone.
    @ObservationIgnored private let day: JournalDay?

    /// When the sheet was opened, which is the whole of what decides whether
    /// the live fix is a fact about the day being written or about a week
    /// later.
    @ObservationIgnored private let now: Date

    /// The zone the day's midnight is measured in and its photographs' hours
    /// are read in — the device's, which is the one the Entry is written in.
    @ObservationIgnored private let timeZone: TimeZone

    /// - Parameters:
    ///   - places: where the surrounding places are read from, and what puts
    ///     names to the positions the day's photographs carry. `nil` is a
    ///     widget with no map behind it — nothing to offer, ever, which is
    ///     what a preview and every test of something else want.
    ///   - library: where the day's photographs are read from. `nil` is a
    ///     widget offering the live fix and nothing else.
    ///   - day: the Journal Day being written about, whose photographs are the
    ///     ones read. `nil` is the same as no library.
    ///   - now: when the sheet was opened.
    ///   - timeZone: where the day's midnight is measured, and the stretch
    ///     of it the library is read for.
    public init(
        from places: (any Places)? = nil,
        photographsFrom library: (any PhotoLibrary)? = nil,
        for day: JournalDay? = nil,
        at now: Date = .now,
        in timeZone: TimeZone = .current
    ) {
        self.places = places
        self.library = library
        self.day = day
        self.now = now
        self.timeZone = timeZone
    }

    /// The place the widget offers: the first place of the first run, which is
    /// the best of everything found once both orderings have had their say.
    public var offered: Place? {
        guard case .offering(let runs) = state else { return nil }
        return runs.first?.places.first
    }

    /// Looks for the places, as far as that is allowed without asking anybody
    /// anything.
    ///
    /// Called with the sheet going on screen. A permission nobody has been
    /// asked about is not asked here — it is offered, and ``askToLook()`` is
    /// what the offer leads to.
    public func look() async {
        let further = whatIsLeftToAsk()
        guard readable else {
            couldLookFurther = further
            return state = .nothingToOffer
        }

        // Nothing to tap while it is being read, and the offer back afterwards
        // — otherwise a finger landing on it mid-read sets a second reading
        // going behind the first, and which of the two lands last decides what
        // the sheet ends up showing.
        couldLookFurther = nil
        state = .looking
        settle(on: await read())
        couldLookFurther = further
    }

    /// Asks for whatever is left to ask for, because the user said to look —
    /// and offers what comes back.
    ///
    /// The only thing in Aujour that ever asks where the device is, and one of
    /// the two that ask for the photo library. A refusal leaves whatever was
    /// already on offer and says nothing about the refusal: they answered the
    /// question that was put to them, and the answer was no.
    public func askToLook() async {
        guard let asking = couldLookFurther else { return }

        state = .looking
        // Before the asking rather than after it, so that a permission alert
        // dismissed without an answer is not an offer to ask that comes back
        // for ever. Whatever the answers turn out to be, this question has now
        // been put.
        couldLookFurther = nil

        if asking != .theDaysPhotographs { _ = await places?.ask() }
        if asking != .theDevicesLocation { _ = await library?.ask() }
        settle(on: await read())
    }

    // MARK: - Reading

    /// Whether anything at all may be read without asking first.
    private var readable: Bool {
        places?.access == .allowed || (library?.access == .allowed && day != nil)
    }

    /// What there is left to be asked about.
    ///
    /// The library counts only where there is a day to read it for and a map
    /// to name what it finds: without either, granting it would add nothing to
    /// the offer, and asking for a permission that changes nothing is the
    /// worst kind of asking.
    private func whatIsLeftToAsk() -> ToLookFurther? {
        let theDevice = places?.access == .undecided
        let theLibrary = library?.access == .undecided && day != nil && places != nil

        switch (theDevice, theLibrary) {
        case (true, true): return .both
        case (true, false): return .theDevicesLocation
        case (false, true): return .theDaysPhotographs
        case (false, false): return nil
        }
    }

    /// Both answers, read at once and put in the order they are worth offering
    /// in — as two runs rather than one list, so the screen can say which is
    /// which.
    private func read() async -> [SuggestedPlaces] {
        // Together, because they are two independent round trips and a sheet
        // is waiting on the pair of them.
        async let photographed = placesTheDayWasPhotographedIn()
        async let around = placesAroundTheDeviceNow()

        let (fromTheDay, fromNow) = await (photographed, around)
        let nearby = SuggestedPlaces(from: .nearby, places: fromNow)
        let theDays = SuggestedPlaces(from: .theDaysPhotographs, places: fromTheDay)

        return withoutRepeats(theDayIsStillOn ? [nearby, theDays] : [theDays, nearby])
    }

    /// Whether the day being written about is the one still being lived, which
    /// is what makes the live fix worth as much as a photograph of it.
    ///
    /// Asked of the day's own midnight-to-midnight stretch rather than by
    /// comparing Journal Days, because that is the question: not "is this
    /// today's Entry" but "is a fix taken now a fix taken on this day". The
    /// Rollover Hour decides the first and has nothing to say about the
    /// second — at 1 AM under a 4 AM rollover the Entry is yesterday's, and a
    /// fix taken now is not where anybody was during yesterday's daylight.
    private var theDayIsStillOn: Bool {
        guard let day else { return true }
        return day.span(in: timeZone).contains(now)
    }

    private func placesAroundTheDeviceNow() async -> [Place] {
        // Never asks, and reads nothing where it may not — the seam's first
        // promise, and what keeps a system alert out from in front of somebody
        // who only opened a sheet.
        guard let places, places.access == .allowed else { return [] }
        return await places.around().toOffer
    }

    /// The places the day's own photographs were taken, earliest first.
    ///
    /// The whole of the bounded-lookup promise lives in these few lines, and
    /// in the order of them: the positions are gathered into stops
    /// (``PhotographedStop/across(_:within:)``) and cut down to
    /// ``asManyStopsAsAreWorthNaming`` *before* a single name is asked for. A
    /// day of two hundred photographs and a day of three cost the same handful
    /// of lookups.
    private func placesTheDayWasPhotographedIn() async -> [Place] {
        guard let places, let library, let day, library.access == .allowed else { return [] }

        let photographs = await library.photographs(during: day.span(in: timeZone))
        let stops = Self.worthNaming(PhotographedStop.across(photographs))
        guard !stops.isEmpty else { return [] }

        return await withTaskGroup(of: (Int, Place?).self) { naming in
            for (at, stop) in stops.enumerated() {
                naming.addTask { (at, await Self.name(stop, with: places)) }
            }

            var named: [Int: Place] = [:]
            for await (at, place) in naming { named[at] = place }
            // Back into the order the day happened in, whichever lookup
            // answered first — and without the ones nothing could name.
            return stops.indices.compactMap { named[$0] ?? nil }
        }
    }

    /// The stops worth spending a lookup on, earliest first.
    ///
    /// A day that went to more places than that is cut down by how many
    /// photographs each stop holds: where the day was spent is where most of
    /// its pictures were taken, and a single frame through a train window is
    /// what gives way. Ties go to the earlier stop, so the same day always
    /// comes out the same way.
    private static func worthNaming(_ stops: [PhotographedStop]) -> [PhotographedStop] {
        guard stops.count > asManyStopsAsAreWorthNaming else { return stops }

        return
            stops
            .sorted {
                $0.photographs == $1.photographs
                    ? $0.arrivedAt < $1.arrivedAt
                    : $0.photographs > $1.photographs
            }
            .prefix(asManyStopsAsAreWorthNaming)
            .sorted { $0.arrivedAt < $1.arrivedAt }
    }

    /// One stop, named.
    ///
    /// Given an id of its own rather than the looked-up place's, because the
    /// ids these arrive with belong to whatever named them and two stops can
    /// come back with the same one. A row in a picker has to be tellable from
    /// the row above it, and the moment the day got there is what tells two
    /// stops apart when nothing else does.
    private static func name(
        _ stop: PhotographedStop,
        with places: any Places
    ) async -> Place? {
        guard let there = await places.place(at: stop.centre) else { return nil }

        return Place(
            id: "photographed:\(there.id)@\(stop.arrivedAt.timeIntervalSince1970)",
            name: there.name,
            region: there.region
        )
    }

    /// One row per place across the whole sheet, keeping the first of any
    /// repeats — and dropping a run that has nothing left in it.
    ///
    /// Two things make the same place turn up twice. Somebody still sitting
    /// where they were photographed is found both ways at once, and the same
    /// café under both headings reads as a bug. And a day spent wandering one
    /// neighbourhood makes several stops that are genuinely apart on the
    /// ground and all come back named "Saint-Germain-des-Prés", because that
    /// is what is there — which is a picker with one word in it four times
    /// over.
    ///
    /// Across the runs and not within each, so that a place found both ways
    /// appears under the heading that found it *best*: the ordering above has
    /// already decided which run that is, and first wins.
    private func withoutRepeats(_ runs: [SuggestedPlaces]) -> [SuggestedPlaces] {
        var seen: Set<String> = []
        return runs.compactMap { run in
            let kept = run.places.filter { seen.insert($0.name).inserted }
            return kept.isEmpty ? nil : SuggestedPlaces(from: run.from, places: kept)
        }
    }

    private func settle(on found: [SuggestedPlaces]) {
        state = found.isEmpty ? .nothingToOffer : .offering(found)
    }

    /// How many of a day's stops are worth putting a name to.
    ///
    /// Four: a list somebody reads at arm's length while a sentence waits, and
    /// four round trips to a map server is what a sheet can spend without the
    /// offer arriving after the user has given up and typed the place. A day
    /// that went to more places than this still offers its four biggest, and
    /// the field is what the fifth is answered with.
    static let asManyStopsAsAreWorthNaming = 4
}
