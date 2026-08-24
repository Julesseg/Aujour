import Foundation

/// Somewhere a day stopped, as its photographs recorded it: the positions that
/// sit together, taken as one.
///
/// A day is not a list of coordinates. Somebody photographs their lunch four
/// times from the same table, and what they would write in their journal is
/// one café and not four. So the day's positions are gathered into stops
/// before anything else looks at them, and it is the stop that gets a name.
///
/// ## This is what keeps the naming bounded
///
/// Putting a name to a position is a round trip to a map server, and a day can
/// hold two hundred photographs. Naming them and then folding the duplicates
/// away would be two hundred lookups to produce three rows, every time a sheet
/// opened — so the folding happens *here*, over arithmetic, and only the
/// handful that comes out the other side is ever named
/// (``PlaceSuggestions/asManyStopsAsAreWorthNaming``). What a day costs is
/// therefore fixed by the number of places it went, and capped above that,
/// however many pictures were taken at each.
public struct PhotographedStop: Hashable, Sendable {
    /// The middle of the positions gathered here — what gets looked up, and
    /// the only position anything above this ever sees.
    public let centre: Coordinate

    /// When the day got here: the earliest photograph of the stop.
    ///
    /// The earliest rather than the middle or the last, because this becomes
    /// the time written beside the place — "Café de Flore, 11:04" — and what
    /// somebody means by that is when they arrived, not the average moment of
    /// their lunch.
    public let arrivedAt: Date

    /// How many photographs were taken here.
    ///
    /// Read only when a day went to more places than are worth naming, where
    /// it decides which of them to name: the spot that holds most of the day's
    /// pictures is where the day was spent, and a single frame taken through a
    /// train window is not.
    public let photographs: Int

    public init(centre: Coordinate, arrivedAt: Date, photographs: Int) {
        self.centre = centre
        self.arrivedAt = arrivedAt
        self.photographs = photographs
    }
}

extension PhotographedStop {
    /// The stops a day made, worked out from the positions its photographs
    /// carry — earliest first, which is the order the day happened in.
    ///
    /// Photographs with no position are dropped rather than guessed at, and a
    /// day where every one of them is like that comes back empty: that is a
    /// widget with no places from photographs, which falls back to the live
    /// fix and is answered by typing after that.
    ///
    /// The grouping is a single pass in the order the day took them. Each
    /// photograph joins the first stop whose centre is within ``sameSpot``
    /// metres, and starts a new one otherwise; a stop's centre is the mean of
    /// what it holds, so it settles onto the middle of the table rather than
    /// wherever the first picture happened to be taken from.
    ///
    /// Walking down a street therefore comes out as one stop rather than
    /// twelve, because each step is within reach of the last and the centre
    /// follows along. That is the right answer for a journal — a walk is one
    /// thing that happened — and it is the deliberate cost of a rule this
    /// simple: two genuinely different places a short walk apart, photographed
    /// continuously between them, arrive as one. Both of them are still one
    /// tap away in the picker behind the offer, and the field under it is what
    /// "none of these" has always been for.
    ///
    /// - Parameters:
    ///   - photographs: the day's, in any order.
    ///   - sameSpot: how close two positions have to be to be the same place.
    public static func across(
        _ photographs: [DayPhotograph],
        within sameSpot: Double = Self.sameSpot
    ) -> [PhotographedStop] {
        // In the order the day took them, whatever order the library answered
        // in: the grouping walks forward through the day, and "the earliest
        // photograph of this stop" is only the first one seen if it does.
        let positioned =
            photographs
            .compactMap { photograph in photograph.position.map { (at: $0, when: photograph.takenAt) } }
            .sorted { $0.when < $1.when }

        var gathering: [Gathering] = []
        for photograph in positioned {
            if let joined = gathering.firstIndex(where: {
                $0.centre.metres(to: photograph.at) <= sameSpot
            }) {
                gathering[joined].take(photograph.at)
            } else {
                gathering.append(Gathering(from: photograph.at, at: photograph.when))
            }
        }

        // Already earliest-first: a stop is appended the moment the day first
        // reaches it, and the day was walked forward.
        return gathering.map(\.stop)
    }

    /// How close two positions have to be to be the same place.
    ///
    /// A hundred and fifty metres: a building and its terrace and the pavement
    /// outside it, not the next café along. Wider than
    /// ``Surroundings/armsReach``, and deliberately — that one decides whether
    /// somebody is *in* a named place, which is a claim about them; this one
    /// only decides whether to spend one lookup or two, and splitting a park
    /// into four rows is the worse of the two mistakes it can make.
    public static let sameSpot: Double = 150
}

/// A stop while it is still being gathered — the running mean of the positions
/// taken so far, which is what the next photograph is measured against.
private struct Gathering {
    private var latitude: Double
    private var longitude: Double
    private var count: Int
    private let arrivedAt: Date

    init(from position: Coordinate, at moment: Date) {
        self.latitude = position.latitude
        self.longitude = position.longitude
        self.count = 1
        self.arrivedAt = moment
    }

    var centre: Coordinate {
        Coordinate(latitude: latitude / Double(count), longitude: longitude / Double(count))
    }

    var stop: PhotographedStop {
        PhotographedStop(centre: centre, arrivedAt: arrivedAt, photographs: count)
    }

    /// Sums rather than averages as it goes, so that the hundredth photograph
    /// of a stop counts for exactly as much as the first.
    ///
    /// Plain arithmetic on degrees, which is a flat-earth mean — wrong by
    /// nothing at all across the couple of hundred metres a stop spans, and
    /// wrong at the antimeridian in a way no day of photographs will ever
    /// notice.
    mutating func take(_ position: Coordinate) {
        latitude += position.latitude
        longitude += position.longitude
        count += 1
    }
}
