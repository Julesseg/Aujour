import Foundation
import AujourCore

/// The journal a UI test asked for, or `nil` — which is everybody else.
///
/// The XCUITest suite drives the app from another process, so the two things
/// it needs, it can only ask for at launch:
///
/// - **A folder of its own.** Otherwise one test's Entries are the next
///   test's journal, and "this day has not been written" stops being a thing
///   any test can claim. It is a folder *inside the app's own Documents*
///   rather than a path the test makes up, because the test's sandbox is not
///   the app's — a temporary directory belonging to the runner is one the app
///   cannot write to.
/// - **A Content Template.** Spawning is most of what M1's Today view does,
///   and nothing in the app can set a template until the settings screen
///   lands.
///
/// Inert unless the launch environment says otherwise, and read exactly once,
/// here — the app has no other back door into where the journal lives.
enum UITestingJournal {
    /// The name of a folder under the app's Documents to journal into.
    static let folderKey = "AUJOUR_UITEST_JOURNAL_FOLDER"

    /// The Content Template new Entries are spawned from.
    static let contentTemplateKey = "AUJOUR_UITEST_CONTENT_TEMPLATE"

    static func fromLaunchEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Journal? {
        guard let folder = environment[folderKey], !folder.isEmpty else { return nil }
        // One folder name, not a path: a `/` or a `..` here would put the
        // journal somewhere neither the app nor the test meant.
        guard !folder.contains("/"), folder != ".", folder != ".." else { return nil }

        var settings = JournalSettings.default
        if let contentTemplate = environment[contentTemplateKey] {
            settings.contentTemplate = contentTemplate
        }

        let root = URL.documentsDirectory
            .appending(path: "UITests", directoryHint: .isDirectory)
            .appending(path: folder, directoryHint: .isDirectory)

        return Journal(
            locator: JournalRootLocator(
                // Pinned rather than looked up: a simulator with no iCloud
                // account would answer differently from a developer's Mac,
                // and a UI test may not depend on which.
                iCloudDocuments: { nil },
                onThisDeviceDocuments: { root },
                lastUsedLocation: { .onThisDevice },
                rememberLocation: { _ in }
            ),
            settings: settings
        )
    }
}
