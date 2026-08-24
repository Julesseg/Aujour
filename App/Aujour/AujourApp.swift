import SwiftUI

@main
struct AujourApp: App {
    /// A UI test journals into a folder of its own; everyone else journals
    /// into theirs (`UITestingJournal`).
    @State private var journal: Journal

    /// How this device wants the app to look. Made here because there is one
    /// per app and it outlives every screen — the journal folder can change
    /// underneath it and the appearance does not.
    @State private var appearance: DeviceAppearance

    init() {
        let journal = UITestingJournal.fromLaunchEnvironment() ?? Journal()
        _journal = State(wrappedValue: journal)
        // Handed the journal's own device settings rather than making a store
        // of its own: two `DeviceSettingsStore`s over one `UserDefaults` would
        // each write settings the other never hears about, so a theme chosen
        // on the settings sheet would not reach the appearance until a
        // relaunch.
        _appearance = State(wrappedValue: DeviceAppearance(settings: journal.deviceSettings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(journal: journal)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
