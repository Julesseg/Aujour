import Foundation

/// The time of day at which the current Journal Day advances.
///
/// Defaults to midnight, which matches Obsidian's daily-notes behavior
/// exactly: with a midnight rollover, the Journal Day is simply the local
/// calendar date. Pushing it later keeps late-night writing on the day being
/// described — with a 4 AM rollover, 1 AM on March 2nd is still March 1st.
public struct RolloverHour: Hashable, Sendable, Codable {
    /// Hour of the local day, 0...23.
    public let hour: Int

    /// Fails for any hour outside 0...23, so an out-of-range setting can
    /// never reach the resolution logic.
    public init?(hour: Int) {
        guard (0...23).contains(hour) else { return nil }
        self.hour = hour
    }

    /// The default: the Journal Day is the local calendar date.
    public static let midnight = RolloverHour(hour: 0)!

    /// Whether a local wall-clock hour is at or past the rollover — the whole
    /// of the "has the Journal Day turned yet?" decision.
    func hasPassed(byLocalHour localHour: Int) -> Bool {
        localHour >= hour
    }
}

// Coded as a bare hour, and validated on the way in: the setting travels
// through iCloud key-value storage (ADR 0003), so a corrupt or hand-edited
// value is refused rather than silently resolving days against hour 99.
extension RolloverHour {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hour = try container.decode(Int.self)
        guard let rolloverHour = RolloverHour(hour: hour) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Rollover Hour must be between 0 and 23, got \(hour)"
            )
        }
        self = rolloverHour
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hour)
    }
}
