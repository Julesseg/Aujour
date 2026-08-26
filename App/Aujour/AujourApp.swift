import SwiftUI

@main
struct AujourApp: App {
    /// A UI test journals into a folder of its own; everyone else journals
    /// into theirs (`UITestingJournal`).
    @State private var journal: Journal

    /// How this device wants the app to look. Made here because there is one
    /// per app and it outlives every screen — the journal folder can change
    /// underneath it and the appearance does not.
    ///
    /// Handed the journal's own device settings rather than making a store of
    /// its own: two `DeviceSettingsStore`s over one `UserDefaults` would each
    /// write settings the other never hears about, so a theme chosen on the
    /// settings sheet would not reach the appearance until a relaunch. It is
    /// also what keeps a UI test's choices apart from the device's, since a
    /// test's journal already keeps a suite of its own.
    @State private var appearance: DeviceAppearance

    init() {
        let journal = UITestingJournal.fromLaunchEnvironment() ?? Journal()
        _journal = State(wrappedValue: journal)
        _appearance = State(wrappedValue: DeviceAppearance(settings: journal.deviceSettings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(journal: journal, appearance: appearance)
                // The three ways this device's choices reach the app, all of
                // them here at the top: the whole window is drawn in the
                // chosen appearance and tinted the chosen colour, and the
                // editor is told what to write in wherever it ends up being
                // pushed.
                .preferredColorScheme(appearance.colorScheme)
                .tint(appearance.accentColor)
                .environment(\.editorLook, appearance.editorLook)
        }
    }
}
