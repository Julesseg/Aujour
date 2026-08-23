import Foundation
import Observation

/// Somewhere the device can name, as everything above CoreLocation sees it.
///
/// A name and, where there is one, enough of an address to tell it from the
/// other place of the same name two streets over. No coordinate and no map:
/// what a `{{location}}` widget does with a place is write it into a sentence,
/// and neither of those is a thing anybody writes. How far off it is is not
/// here either — that belongs to ``NearbyPlace``, which is where it is used
/// and where it stops.
public struct Place: Hashable, Sendable, Identifiable {
    /// What the device calls it. Opaque here, and only ever used to tell one
    /// row of the picker from another.
    public let id: String

    /// What it is called — "Café de Flore", "Paris". This is the whole of what
    /// goes in the Entry.
    public let name: String

    /// Where it is, for somebody choosing between two of them — the street, or
    /// the town. `nil` for a place that is its own address.
    public let region: String?

    public init(id: String, name: String, region: String? = nil) {
        self.id = id
        self.name = name
        self.region = region
    }

    /// The plain markdown that stands where the token was.
    ///
    /// The name alone, deliberately. A `{{location}}` is written in the middle
    /// of somebody's own sentence — "walked home from {{location}}" — and an
    /// address dropped into it would be the app finishing the sentence its own
    /// way. The region is on screen while the place is being chosen, which is
    /// where telling two of them apart matters, and it stops there.
    public var written: String { name }
}

/// Whether Aujour may ask the device where it is.
///
/// Three answers rather than a `Bool`, for the reason ``PhotoLibraryAccess``
/// has three: an undecided device is one worth offering to look at, a refused
/// one is a widget that offers nothing, and only an allowed one is ever read.
public enum PlaceAccess: Hashable, Sendable {
    /// Nobody has been asked yet.
    case undecided

    /// Aujour may ask where the device is — precisely, or roughly.
    case allowed

    /// The user said no, or this device does not allow it at all.
    case refused
}

/// One named place, and how far off the device said it was.
///
/// The distance is here and nowhere else: it decides which of the places
/// around somebody is the one they are *in*, and once that is decided it is of
/// no further use to anybody. Nothing carries it into a ``Place``, because
/// nothing writes it into an Entry.
public struct NearbyPlace: Hashable, Sendable {
    public let place: Place

    /// How far off, in metres.
    public let metresAway: Double

    public init(place: Place, metresAway: Double) {
        self.place = place
        self.metresAway = metresAway
    }
}

/// Everything the device could say about where it is: the named places around
/// it, and the area they all sit in.
///
/// Two answers rather than one, because they are two different kinds of true.
/// A café has a name somebody would actually write; a neighbourhood is vaguer
/// and never wrong. Which of them leads the offer is
/// ``Surroundings/toOffer``'s to decide, and that decision is the whole reason
/// the two arrive apart.
public struct Surroundings: Hashable, Sendable {
    /// The places with names of their own, nearest first.
    public let named: [NearbyPlace]

    /// The area they are in — the neighbourhood, or the town. `nil` for a
    /// device that could not put a name to it.
    public let area: Place?

    public init(named: [NearbyPlace] = [], area: Place? = nil) {
        self.named = named
        self.area = area
    }

    /// The places to offer, the first being the one the widget offers.
    ///
    /// The nearest named place leads only when it is close enough to be where
    /// somebody actually *is*; otherwise the area does, and the named place is
    /// one tap away in the list behind it.
    ///
    /// That rule is the whole of the judgement here, and it exists because of
    /// what the two mistakes cost. Standing in a café, "Café de Flore" is the
    /// answer and offering "Saint-Germain" wastes the widget. Standing in a
    /// street with a pharmacy fifty doors down, "Pharmacie du Marché" is a
    /// wrong answer somebody would confirm with one tap — and a wrong answer
    /// written into somebody's journal is the one thing this must never do.
    /// Vague and right beats specific and wrong, so the specific one has to
    /// earn the lead by being close.
    ///
    /// Everything found is in the list either way: the picker is what "none of
    /// these" is for, and the field under it is what "none of these either" is
    /// for.
    public var toOffer: [Place] {
        let places = named.map(\.place)
        guard let area else { return places }
        guard let nearest = named.first else { return [area] }

        return nearest.metresAway <= Self.armsReach
            ? [nearest.place, area] + places.dropFirst()
            : [area] + places
    }

    /// How close a named place has to be to be *where somebody is* rather than
    /// merely near them — and so to lead the offer instead of the area.
    ///
    /// A hundred metres: across a square, not across a neighbourhood.
    static let armsReach: Double = 100
}

/// Where the device is, as the `{{location}}` widget sees it.
///
/// The fourth seam between the domain and the device, after the Journal Store,
/// Day Data and the photo library, and it is shaped by the same two promises:
///
/// - **Reading never asks.** ``around()`` answers with nothing at all where
///   access is anything but granted. Asking is ``ask()``, which happens
///   because the user tapped a widget and said to look — never because a day
///   was opened, and never because a sheet came up.
/// - **Reading never fails.** A device with the radios off, a fix that never
///   arrives, a lookup that comes back empty: all of them are no places to
///   offer, which is a sheet the user types the place into. Nothing about
///   CoreLocation ever reaches the user as an error, because there is nothing
///   they could do with one — the question in front of them is "where were
///   you", and they know the answer (ADR 0001).
public protocol Places: Sendable {
    /// Where the permission stands, without asking for it.
    var access: PlaceAccess { get }

    /// Puts the system's question in front of the user, and answers what they
    /// said.
    ///
    /// Called because somebody asked for the place to be found, and at no
    /// other time. A permission already decided — granted or refused — is left
    /// decided and answered from what is already known, because the way back
    /// from a refusal is Settings and not another alert.
    func ask() async -> PlaceAccess

    /// Everything the device can say about where it is now — or nothing at
    /// all, which is also what an unallowed device answers.
    ///
    /// The named places come back nearest first, which is the seam's to
    /// promise: which one is closest is a fact about where somebody is
    /// standing, and measuring it is the device's job. What is done with that
    /// order is ``Surroundings/toOffer``'s, above this line and unit-tested
    /// there.
    func around() async -> Surroundings
}

/// What a `{{location}}` widget offers the user: where the device says they
/// are, and the places around it to choose instead.
///
/// A day is written up in the evening, or a week later, and the phone that was
/// there is the one being written on — so the widget offers the place rather
/// than asking somebody to spell it. Which places those are is the only
/// question here, and it has one answer: whatever the device names around
/// itself, in the order it named them.
///
/// It holds no map and no permission alert. Both are the app's, behind
/// ``Places`` — which is what lets every rule here be unit-tested on Linux
/// against places that are said rather than found.
///
/// ## Nothing on offer is the ordinary case
///
/// A refused device, a device that will not say, and somewhere with no place
/// worth naming all come out the same: no offer at all. None of them is a
/// failure and none of them is said out loud, because the sheet is answerable
/// either way — the place is typed, which is what answering a placeholder was
/// before there was a device to ask.
@MainActor
@Observable
public final class PlaceSuggestions {
    /// What the sheet should be showing above the field the place is typed in.
    public enum State: Hashable, Sendable {
        /// No offer. A refused device, one with nothing to say, or nowhere
        /// with a place to name.
        case nothingToOffer

        /// Nobody has been asked about the device's location yet, so there is
        /// something worth offering to look for — and asking is the user's to
        /// set going.
        case couldLook

        /// The device is being asked. On screen while it is, because finding a
        /// place is a fix and then a lookup, and a sheet that showed nothing
        /// meanwhile would read as a device that had answered "nowhere".
        case looking

        /// The places to offer, the first of them being the offer itself.
        case offering([Place])
    }

    public private(set) var state: State = .nothingToOffer

    /// The device, or none at all — which is a preview, and a test of
    /// something else, and offers nothing.
    @ObservationIgnored private let places: (any Places)?

    /// - Parameter places: where the surrounding places are read from. `nil`
    ///   is a widget with no device behind it — nothing to offer, ever, which
    ///   is what a preview and every test of something else want.
    public init(from places: (any Places)? = nil) {
        self.places = places
    }

    /// The place the widget offers: the nearest one the device named.
    public var offered: Place? {
        guard case .offering(let around) = state else { return nil }
        return around.first
    }

    /// Looks for the place, if that is allowed without asking anybody
    /// anything.
    ///
    /// Called with the sheet going on screen. A device nobody has been asked
    /// about is not asked here — it is offered, and ``askToLook()`` is what
    /// the offer leads to.
    public func look() async {
        guard let places else { return state = .nothingToOffer }

        switch places.access {
        case .refused:
            state = .nothingToOffer
        case .undecided:
            state = .couldLook
        case .allowed:
            await read(places)
        }
    }

    /// Asks for the device's location, because the user said to look — and
    /// offers what is around if they allowed it.
    ///
    /// The only thing in Aujour that ever asks where the device is. A refusal
    /// leaves nothing on offer and says nothing about it: they answered the
    /// question that was put to them, and the answer was no.
    public func askToLook() async {
        guard let places else { return }

        state = .looking
        guard await places.ask() == .allowed else { return state = .nothingToOffer }
        await read(places)
    }

    private func read(_ places: any Places) async {
        state = .looking
        // The first is the offer and the rest are the picker, and both are
        // this one answer put in the order it is worth offering in.
        let around = await places.around().toOffer
        state = around.isEmpty ? .nothingToOffer : .offering(around)
    }
}
