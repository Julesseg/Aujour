import SwiftUI
import AujourCore

/// How this device wants Aujour to look, live.
///
/// The device-local half of the settings seam, as SwiftUI needs it: a value
/// that changes under a running app, and a view that redraws when it does.
/// It is read through `UserDefaults` and never through iCloud (ADR 0003) —
/// an iPhone in dark and an iPad in light are not in disagreement about
/// anything, and nothing here shapes a file in the journal folder.
///
/// The appearance and nothing else: the daily reminder is the other reader of
/// this seam and lives in Core, where what it has to decide can be tested; the
/// accents and editor fonts are still M6's.
///
/// Handed the store rather than making one, and the same store the reminder
/// reads — a settings group reports its changes to whoever is holding it, and
/// a second `DeviceSettingsStore` over the same `UserDefaults` would write a
/// theme this one never hears about.
@MainActor
@Observable
final class DeviceAppearance {
    private let settings: DeviceSettingsStore

    private(set) var theme: Theme

    /// Held for as long as this object is: cancelled with it, and reporting
    /// every change until then.
    private var watchingTheSettings: SettingsObservation?

    init(settings: DeviceSettingsStore = DeviceSettingsStore(storedOn: LocalSettingsStorage())) {
        self.settings = settings
        self.theme = settings.settings.theme
        watchingTheSettings = settings.observe { [weak self] in self?.theme = $0.theme }
    }

    /// What SwiftUI is told to draw in, where `nil` is "whatever the system is
    /// doing" — the default, and the only one of the three that is not an
    /// instruction to override the system.
    var colorScheme: ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
