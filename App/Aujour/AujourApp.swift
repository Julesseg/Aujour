import SwiftUI

@main
struct AujourApp: App {
    var body: some Scene {
        WindowGroup {
            // A UI test journals into a folder of its own; everyone else
            // journals into theirs (`UITestingJournal`).
            ContentView(journal: UITestingJournal.fromLaunchEnvironment() ?? Journal())
        }
    }
}
