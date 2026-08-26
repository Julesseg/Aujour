import Foundation

/// The settings that belong to this device alone: how the app looks, what
/// the editor reads like, and when it nudges.
///
/// Nothing here shapes what gets written into the Journal, so nothing here
/// needs to agree with the user's other devices (ADR 0003) — a dark-themed
/// iPhone and a light-themed iPad are not in conflict, and a reminder is a
/// property of the device that buzzes.
public struct DeviceSettings: Equatable, Sendable {
    public var theme: Theme
    public var accent: Accent
    public var editorFont: EditorFont

    /// When to nudge the user to journal, or `nil` for no reminder — the
    /// state until a time is chosen in the welcome.
    public var dailyReminder: TimeOfDay?

    /// Whether this device has been through the welcome.
    ///
    /// Here rather than on the synced seam for the reason the reminder is: it
    /// is about this install having been introduced to the app, and an iPad
    /// added a year later has not been. It shapes nothing in the Journal
    /// (ADR 0003).
    public var hasBeenWelcomed: Bool

    public init(
        theme: Theme = .system,
        accent: Accent = .driftwood,
        editorFont: EditorFont = .default,
        dailyReminder: TimeOfDay? = nil,
        hasBeenWelcomed: Bool = false
    ) {
        self.theme = theme
        self.accent = accent
        self.editorFont = editorFont
        self.dailyReminder = dailyReminder
        self.hasBeenWelcomed = hasBeenWelcomed
    }

    public static let `default` = DeviceSettings()
}

/// Light, dark, or whatever the system is doing.
public enum Theme: String, Hashable, Sendable, CaseIterable {
    case system
    case light
    case dark
}

/// The one colour Aujour uses to mean *this one*: the selected day, an
/// answered Widget, a checkbox, the way back out of a sheet.
///
/// The identity's named set and never a colour the user mixes. Two reasons,
/// and the second is why there is a set at all rather than a wheel: the app
/// cannot promise that a colour somebody mixed will carry a tick box at the
/// size a tick box is drawn at, and every one of these is held above a
/// contrast floor so that it does (ADR 0006).
///
/// The names are what the colours are called, not what they are worth: which
/// shade of `sage` a device draws — and it is a different one in light and in
/// dark — is the app layer's, where there is a screen to resolve it against.
public enum Accent: String, Hashable, Sendable, CaseIterable {
    case driftwood
    case terracotta
    case clay
    case ochre
    case olive
    case sage
    case harbour
    case plum
    case graphite
}

/// The typeface and size the editor renders Entries in.
public struct EditorFont: Equatable, Sendable {
    /// The curated set — a journal is read for a long time, so the choice is
    /// three good options rather than every font on the device.
    public enum Family: String, Hashable, Sendable, CaseIterable {
        case system
        case serif
        case monospaced
    }

    /// Four steps rather than a number to dial in.
    ///
    /// This is a writing preference — how big the user wants their own words,
    /// the way somebody picks a pen — and not a typographer's control. Four
    /// named steps are one tap each and cannot land on a half point nobody
    /// meant, and the range they cover is the one the identity draws prose
    /// over.
    ///
    /// It governs the Entry alone. Everything else — settings rows, the
    /// calendar, every label in the app — follows the system's own text size,
    /// because that is a decision the user already made for everything they
    /// read.
    public enum Size: String, Hashable, Sendable, CaseIterable {
        case small
        case medium
        case large
        case extraLarge
    }

    public var family: Family
    public var size: Size

    public init(family: Family, size: Size) {
        self.family = family
        self.size = size
    }

    public static let `default` = EditorFont(family: .system, size: .medium)
}

/// A time on the clock, with no date attached.
public struct TimeOfDay: Hashable, Sendable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    /// Fails for anything off the clock, so an impossible reminder time can
    /// never reach the scheduler.
    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// 24-hour `HH:mm`. This is storage, not display — what the user sees is
    /// formatted in their locale by the UI.
    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    init?(_ stored: String) {
        let parts = stored.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }
        self.init(hour: hour, minute: minute)
    }

    /// The time as this reader's own clock writes it — 12- or 24-hour,
    /// whichever their region is on.
    ///
    /// The one place a `TimeOfDay` is read rather than stored, so it is the
    /// one place a locale gets a say: `description` stays `HH:mm` wherever the
    /// user is, because that is what goes into storage and what is read back.
    ///
    /// Measured off a day with no daylight saving in it, deliberately. What is
    /// being written down is a clock face and not a moment — nine in the
    /// evening is nine in the evening on the two days a year the local one has
    /// an hour missing from it, and a time hung off *those* would be a setting
    /// that read back as the wrong hour twice a year.
    public func spelledOut(locale: Locale = .current) -> String {
        let noRules = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = noRules

        let midnight = Date(timeIntervalSince1970: 0)
        let atThatTime =
            calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: midnight)
            ?? midnight
        return atThatTime.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: noRules)
        )
    }
}

/// Keeps the device-local settings on this device.
///
/// The mirror of `JournalSettingsStore`, and deliberately a different type:
/// it accepts only a `LocalKeyValueStore`, so device preferences cannot be
/// handed the synced seam by accident.
@MainActor
public final class DeviceSettingsStore {
    private let storage: SettingsStorage<DeviceSettings>

    /// - Parameter store: on-device storage — `UserDefaults` in the app, a
    ///   fake in tests. Never the synced seam.
    public init(storedOn store: any LocalKeyValueStore) {
        self.storage = SettingsStorage<DeviceSettings>(store: store)
    }

    public var settings: DeviceSettings { storage.value }

    public func update(_ change: (inout DeviceSettings) -> Void) {
        storage.update(change)
    }

    /// Reports every change, so the UI has one place to listen. Cancel the
    /// returned observation to stop.
    @discardableResult
    public func observe(_ handler: @escaping (DeviceSettings) -> Void) -> SettingsObservation {
        storage.observe(handler)
    }
}

enum DeviceSettingsKey {
    static let theme = "aujour.device.theme"
    static let accent = "aujour.device.accent"
    static let editorFontFamily = "aujour.device.editorFontFamily"
    static let editorFontSize = "aujour.device.editorFontSize"
    static let dailyReminder = "aujour.device.dailyReminder"
    static let hasBeenWelcomed = "aujour.device.hasBeenWelcomed"
}

extension DeviceSettings: SettingsGroup {
    init(storedValues: (String) -> String?) {
        let fallback = DeviceSettings.default
        self.theme = storedValues(DeviceSettingsKey.theme)
            .flatMap(Theme.init(rawValue:)) ?? fallback.theme
        self.accent = storedValues(DeviceSettingsKey.accent)
            .flatMap(Accent.init(rawValue:)) ?? fallback.accent
        self.editorFont = EditorFont(
            family: storedValues(DeviceSettingsKey.editorFontFamily)
                .flatMap(EditorFont.Family.init(rawValue:)) ?? fallback.editorFont.family,
            size: storedValues(DeviceSettingsKey.editorFontSize)
                .flatMap(EditorFont.Size.init(rawValue:)) ?? fallback.editorFont.size
        )
        // An unreadable reminder time leaves the reminder off rather than
        // guessing an hour: a notification at the wrong time is worse than
        // none.
        self.dailyReminder = storedValues(DeviceSettingsKey.dailyReminder).flatMap(TimeOfDay.init)
        // An unreadable value is a device that has not been welcomed, which
        // costs one welcome nobody needed — the other way round is an install
        // that never gets introduced to the app at all.
        self.hasBeenWelcomed = storedValues(DeviceSettingsKey.hasBeenWelcomed)
            .flatMap(Bool.init) ?? fallback.hasBeenWelcomed
    }

    func changedValues(from previous: DeviceSettings) -> [(key: String, value: String?)] {
        var changes: [(key: String, value: String?)] = []
        if theme != previous.theme {
            changes.append((DeviceSettingsKey.theme, theme.rawValue))
        }
        if accent != previous.accent {
            changes.append((DeviceSettingsKey.accent, accent.rawValue))
        }
        if editorFont.family != previous.editorFont.family {
            changes.append((DeviceSettingsKey.editorFontFamily, editorFont.family.rawValue))
        }
        if editorFont.size != previous.editorFont.size {
            changes.append((DeviceSettingsKey.editorFontSize, editorFont.size.rawValue))
        }
        if dailyReminder != previous.dailyReminder {
            changes.append((DeviceSettingsKey.dailyReminder, dailyReminder?.description))
        }
        if hasBeenWelcomed != previous.hasBeenWelcomed {
            changes.append((DeviceSettingsKey.hasBeenWelcomed, String(hasBeenWelcomed)))
        }
        return changes
    }
}
