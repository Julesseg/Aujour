import Foundation
import AujourCore

/// Where the settings that belong to this device alone live: `UserDefaults`,
/// and deliberately nowhere else (ADR 0003).
///
/// The mirror of `SyncedSettingsStorage`, and a separate type rather than the
/// same one with a flag turned off, because that is what makes the rule a
/// compiler's to keep: `DeviceSettingsStore` accepts only a
/// `LocalKeyValueStore`, which iCloud's seam deliberately is not, so a theme
/// or a reminder time cannot reach the iPad by accident.
///
/// A theme is not something two devices can disagree about — a dark iPhone
/// and a light iPad are both right — and a reminder is a property of the
/// device that buzzes. Nothing here shapes what is written into the Journal,
/// so nothing here has to travel.
@MainActor
final class LocalSettingsStorage: LocalKeyValueStore {
    private let onThisDevice: UserDefaults

    init(onThisDevice: UserDefaults = .standard) {
        self.onThisDevice = onThisDevice
    }

    func string(forKey key: String) -> String? {
        onThisDevice.string(forKey: key)
    }

    func setString(_ value: String?, forKey key: String) {
        onThisDevice.setString(value, forKey: key)
    }
}

extension UserDefaults {
    /// Writes a setting, or takes it away.
    ///
    /// A setting turned off is a key that goes, rather than a key holding
    /// nothing: left behind, a daily reminder the user cleared would be read
    /// back and rung. Shared with `SyncedSettingsStorage`, which keeps the
    /// device's copy of the synced settings the same way.
    func setString(_ value: String?, forKey key: String) {
        if let value {
            set(value, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
