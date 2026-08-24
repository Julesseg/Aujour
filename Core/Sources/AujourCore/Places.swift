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
    /// The name alone, deliberately, and whichever way the place was found. A
    /// `{{location}}` is written in the middle of somebody's own sentence —
    /// "walked home from {{location}}" — and anything dropped in beside the
    /// name would be the app finishing the sentence its own way. That goes for
    /// the region, and it goes for the hour a photograph was taken at: the
    /// day's photographs are how Aujour works out *which places to offer*, and
    /// they stop at the offer. What lands in the file is a place, the same
    /// characters whether the device named it or a picture did.
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
/// A café has a name somebody would actually write; a town is vaguer and never
/// wrong. What is made of the pair of them is decided above — a list to offer
/// for today (``Surroundings/toOffer``) or the one name a spot goes by
/// (``Surroundings/bestKnownAs``) — and those two want the pair in different
/// orders, which is the whole reason they arrive apart rather than already
/// ranked.
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
    /// The area leads, always — which in practice is the town, since that is
    /// what a fix reverse-geocodes to. Then the named places around it,
    /// nearest first, as far as ``asManyAsAreWorthOffering``.
    ///
    /// Leading with the town rather than with whatever happens to be nearest
    /// is the whole of the judgement here, and it is about what the two
    /// mistakes cost. Confirming the offer is one tap, so the offer has to be
    /// somewhere the user certainly was. "Paris" is that on every day of the
    /// year; "Pharmacie du Marché", picked because it was the nearest thing
    /// with a name, is a place somebody may only have walked past — and a
    /// wrong answer written into somebody's journal is the one thing this must
    /// never do. Vague and right beats specific and wrong.
    ///
    /// It is also the answer most often wanted. A journal line says where the
    /// day was spent, and that is far more often a town than a shopfront; the
    /// café is one tap down the list for the days it *is* the answer.
    ///
    /// The field under the picker is what "none of these" is for.
    public var toOffer: [Place] {
        let places = named.map(\.place)
        guard let area else { return Array(places.prefix(Self.asManyAsAreWorthOffering)) }
        return Array(([area] + places).prefix(Self.asManyAsAreWorthOffering))
    }

    /// How many places are worth offering from around the device.
    ///
    /// Five, counting the town: a list somebody reads at a glance while a
    /// sentence waits, not a directory of everything with a name within a
    /// couple of minutes' walk. What falls off the end is the furthest, which
    /// is the least likely to be where anybody was.
    ///
    /// The number lives here rather than in whatever asked the map, because it
    /// is a judgement about a picker on a screen and not about what a search
    /// can return.
    static let asManyAsAreWorthOffering = 5

    /// The one thing this spot is best called — a single name rather than a
    /// list, for somewhere the user is not.
    ///
    /// This is what a position out of the day's photographs is put through,
    /// and it is deliberately *not* ``toOffer``'s rule. The two are asked
    /// different questions. Around the device, the question is "what shall I
    /// offer you for today", and a list led by the town is the safe answer.
    /// Around a photograph, the question is "what is this one place", the
    /// answer is one row among the day's other stops, and answering "Paris"
    /// for every one of them would collapse a day of places into a single
    /// useless line.
    ///
    /// A photograph also earns the specific answer in a way a live fix cannot.
    /// Somebody stood there and took a picture, so a café a few metres off is
    /// where they were rather than somewhere they might have walked past —
    /// which is exactly what ``armsReach`` is measuring. Beyond it there is no
    /// such claim, and the town takes over.
    public var bestKnownAs: Place? {
        guard let nearest = named.first else { return area }
        return nearest.metresAway <= Self.armsReach ? nearest.place : (area ?? nearest.place)
    }

    /// How close a named place has to be to be *where somebody was* rather
    /// than merely near them — and so to be what a spot is called instead of
    /// the town.
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
