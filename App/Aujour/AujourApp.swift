import SwiftUI

@main
struct AujourApp: App {
    /// How this device wants the app to look. Made here because there is one
    /// per app and it outlives every screen — the journal folder can change
    /// underneath it and the appearance does not.
    @State private var appearance = DeviceAppearance()

    var body: some Scene {
        WindowGroup {
            // A UI test journals into a folder of its own; everyone else
            // journals into theirs (`UITestingJournal`).
            ContentView(journal: UITestingJournal.fromLaunchEnvironment() ?? Journal())
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
