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

    /// The time of day a photograph put somebody here — "11:04", on a clock
    /// read the way their own device reads one. `nil` for a place the device
    /// found by looking around itself.
    ///
    /// Only a place worked out from the day's photographs has one, and only
    /// such a place could: a photograph knows the hour it was taken, and a
    /// live fix knows nothing except that it is now — which for a Monday
    /// written up on Friday is not a fact about Monday at all.
    ///
    /// Unlike ``region`` this *is* written into the Entry, because it is the
    /// kind of thing somebody writes: "Café de Flore, 11:04" is a line in a
    /// journal and the region would be an address in the middle of one.
    public let atTime: String?

    public init(id: String, name: String, region: String? = nil, atTime: String? = nil) {
        self.id = id
        self.name = name
        self.region = region
        self.atTime = atTime
    }

    /// The plain markdown that stands where the token was.
    ///
    /// The name, and the hour where a photograph could say one. A
    /// `{{location}}` is written in the middle of somebody's own sentence —
    /// "walked home from {{location}}" — so what goes in is what somebody
    /// would have typed there and nothing more: an address dropped into it
    /// would be the app finishing the sentence its own way, which is why the
    /// region stays in the picker where telling two places apart is what
    /// matters.
    ///
    /// It is filled into the field rather than written outright either way, so
    /// the last word on all of this is the user's — a comma and an hour that
    /// does not suit the sentence is deleted before "Add" is ever tapped.
    public var written: String {
        guard let atTime else { return name }
        return "\(name), \(atTime)"
    }
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

    /// What to call somewhere the device is not: the one place a position is
    /// best known as, or `nil` for a position nothing could put a name to.
    ///
    /// The positions are the day's own photographs', gathered into
    /// ``PhotographedStop``s first so that this is asked a handful of times
    /// per sheet rather than once per picture.
    ///
    /// **This one is not gated on the permission**, alone among the members
    /// here, and that is the point of it. Asking what stands at a coordinate
    /// is a question about the map; asking where the device is is a question
    /// about the user, and only the second is what
    /// `NSLocationWhenInUseUsageDescription` is the answer to. The coordinate
    /// arrived from the user's own photo library, which they opened
    /// deliberately — so somebody who refused the one permission and granted
    /// the other is still offered the places their day's pictures were taken,
    /// which is the whole reason the offer rides both.
    ///
    /// Reading still never fails: a lookup that comes back with nothing, or
    /// does not come back at all, is one stop with no name among however many
    /// had one.
    func place(at position: Coordinate) async -> Place?
}
