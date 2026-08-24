import Foundation

/// A position on the earth, as the things above the device pass one around.
///
/// The one coordinate in Aujour, and it exists for exactly one reason: a
/// photograph knows where it was taken and a ``Place`` deliberately does not.
/// Between the two sits the work this type is for — deciding which of a day's
/// photographs were taken in the same spot, so that the spot is named once
/// rather than once per photograph.
///
/// It goes no further than that. Nothing writes a coordinate into an Entry,
/// nothing draws one, and a ``Place`` that has been named has no memory of the
/// one it came from: "48.854, 2.333" is not a thing anybody writes in their
/// journal, which is the whole reason ``Place`` never carried one.
///
/// Here rather than behind CoreLocation because "these two photographs were
/// taken in the same place" is a rule about somebody's day, and a rule that
/// could only be checked by walking around Paris with a phone is one nobody
/// checks. `CLLocation` does the same arithmetic; it is simply not available
/// on the Linux the rest of these rules are tested on.
public struct Coordinate: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// How far apart two positions are, in metres.
    ///
    /// Great-circle distance on a sphere — the haversine formula, which is
    /// what `CLLocation.distance(from:)` answers to within a fraction of a
    /// percent. That fraction is nothing at all to the question being asked of
    /// it: whether two photographs were taken in the same café, decided in
    /// units of a hundred metres.
    public func metres(to other: Coordinate) -> Double {
        let φ1 = latitude * .pi / 180
        let φ2 = other.latitude * .pi / 180
        let Δφ = (other.latitude - latitude) * .pi / 180
        let Δλ = (other.longitude - longitude) * .pi / 180

        let a =
            sin(Δφ / 2) * sin(Δφ / 2)
            + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * Self.earthsRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    /// The mean radius of the earth, in metres.
    private static let earthsRadius: Double = 6_371_000
}
