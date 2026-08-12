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
    public var editorFont: EditorFont

    /// When to nudge the user to journal, or `nil` for no reminder — the
    /// state until a time is chosen in onboarding.
    public var dailyReminder: TimeOfDay?

    public init(
        theme: Theme = .system,
        editorFont: EditorFont = .default,
        dailyReminder: TimeOfDay? = nil
    ) {
        self.theme = theme
        self.editorFont = editorFont
        self.dailyReminder = dailyReminder
    }

    public static let `default` = DeviceSettings()
}

/// Light, dark, or whatever the system is doing.
public enum Theme: String, Hashable, Sendable, CaseIterable {
    case system
    case light
    case dark
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

    public var family: Family

    /// Point size, clamped to `EditorFont.sizeRange`, so any font that exists
    /// is one the editor can actually render.
    public var size: Double {
        didSet { size = EditorFont.clamped(size) }
    }

    public static let sizeRange: ClosedRange<Double> = 11...28

    public init(family: Family, size: Double) {
        self.family = family
        self.size = EditorFont.clamped(size)
    }

    private static func clamped(_ size: Double) -> Double {
        min(max(size, sizeRange.lowerBound), sizeRange.upperBound)
    }

    public static let `default` = EditorFont(family: .system, size: 17)
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
    static let editorFontFamily = "aujour.device.editorFontFamily"
    static let editorFontSize = "aujour.device.editorFontSize"
    static let dailyReminder = "aujour.device.dailyReminder"
}

extension DeviceSettings: SettingsGroup {
    init(storedValues: (String) -> String?) {
        let fallback = DeviceSettings.default
        self.theme = storedValues(DeviceSettingsKey.theme)
            .flatMap(Theme.init(rawValue:)) ?? fallback.theme
        self.editorFont = EditorFont(
            family: storedValues(DeviceSettingsKey.editorFontFamily)
                .flatMap(EditorFont.Family.init(rawValue:)) ?? fallback.editorFont.family,
            size: storedValues(DeviceSettingsKey.editorFontSize)
                .flatMap(Double.init)
                .flatMap { EditorFont.sizeRange.contains($0) ? $0 : nil } ?? fallback.editorFont.size
        )
        // An unreadable reminder time leaves the reminder off rather than
        // guessing an hour: a notification at the wrong time is worse than
        // none.
        self.dailyReminder = storedValues(DeviceSettingsKey.dailyReminder).flatMap(TimeOfDay.init)
    }

    func changedValues(from previous: DeviceSettings) -> [(key: String, value: String?)] {
        var changes: [(key: String, value: String?)] = []
        if theme != previous.theme {
            changes.append((DeviceSettingsKey.theme, theme.rawValue))
        }
        if editorFont.family != previous.editorFont.family {
            changes.append((DeviceSettingsKey.editorFontFamily, editorFont.family.rawValue))
        }
        if editorFont.size != previous.editorFont.size {
            changes.append((DeviceSettingsKey.editorFontSize, String(editorFont.size)))
        }
        if dailyReminder != previous.dailyReminder {
            changes.append((DeviceSettingsKey.dailyReminder, dailyReminder?.description))
        }
        return changes
    }
}
