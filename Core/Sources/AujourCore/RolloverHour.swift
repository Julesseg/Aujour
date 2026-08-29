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

    /// Every hour a day could turn at, in order.
    ///
    /// Here rather than counted to twenty-four by the screen that offers them:
    /// which hours there are is a fact about a Rollover Hour, and a picker
    /// built from a range of `Int` has to deal with the ones that are not.
    public static let everyHourOfTheDay = (0..<24).compactMap(RolloverHour.init(hour:))

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

extension RolloverHour {
    /// The hour as this reader's own clock writes it — 12- or 24-hour,
    /// whichever their region is on.
    ///
    /// The one place a Rollover Hour is read rather than applied, and so the
    /// one place a locale gets a say. Here rather than in either of the two
    /// screens that say it — the settings row it is chosen on, and the page
    /// over a day that has not arrived, which names it as when writing opens
    /// — because they have to name the same hour in the same words, and two
    /// clock formatters is how they would come to disagree.
    ///
    /// Said as a clock face and not as a moment, which is ``TimeOfDay``'s job
    /// and is why this borrows it: the hour a day turns at is nine o'clock on
    /// the two days a year the local clock has an hour missing from it.
    public func spelledOut(locale: Locale = .current) -> String {
        // Never nil: a Rollover Hour is an hour of the clock or it does not
        // exist, which is what its own initializer is for, and nought minutes
        // past one is a time.
        TimeOfDay(hour: hour, minute: 0)!.spelledOut(locale: locale)
    }
}
