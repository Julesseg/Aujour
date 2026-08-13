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
    ///
    /// Spelled out again in `AujourUITests.launchApp`, which sets it: the UI
    /// suite drives the app from another target and imports nothing from it.
    static let folderKey = "AUJOUR_UITEST_JOURNAL_FOLDER"

    /// The Content Template new Entries are spawned from.
    static let contentTemplateKey = "AUJOUR_UITEST_CONTENT_TEMPLATE"

    /// The name of a folder for "Use a custom folder…" to pick, in place of
    /// the Files picker.
    static let folderToPickKey = "AUJOUR_UITEST_FOLDER_TO_PICK"

    @MainActor
    static func fromLaunchEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Journal? {
        guard let folder = environment[folderKey], isAFolderName(folder) else { return nil }

        var settings = JournalSettings.default
        if let contentTemplate = environment[contentTemplateKey] {
            settings.contentTemplate = contentTemplate
        }

        return Journal(
            locator: JournalRootLocator(
                // Pinned rather than looked up: a simulator with no iCloud
                // account would answer differently from a developer's Mac,
                // and a UI test may not depend on which.
                iCloudDocuments: { nil },
                onThisDeviceDocuments: { documentsFolder(named: folder) },
                lastUsedLocation: { .onThisDevice },
                rememberLocation: { _ in },
                // Kept between launches like the app's own, and under a key of
                // this test's own: a folder chosen by one test must never be
                // the next test's journal, and "it survived the relaunch" is
                // the claim being made.
                customRoot: .stored(key: "\(CustomJournalRoot.bookmarkKey).\(folder)")
            ),
            settings: settings
        )
    }

    /// The folder a UI test means to pick, made if it is not there yet — or
    /// `nil`, which is everybody else, and which is what leaves the Files
    /// picker in charge.
    ///
    /// Made here because a folder picked in the Files app always exists, and
    /// there is no picker in a UI test to have made one. It is inside the
    /// app's own Documents for the same reason the test's journal is: the
    /// runner's temporary directory is not somewhere the app can write.
    @MainActor
    static func folderToPick(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let name = environment[folderToPickKey], isAFolderName(name) else { return nil }

        let folder = documentsFolder(named: name)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// One folder name, not a path: a `/` or a `..` here would put the
    /// journal somewhere neither the app nor the test meant.
    private static func isAFolderName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
    }

    private static func documentsFolder(named name: String) -> URL {
        URL.documentsDirectory
            .appending(path: "UITests", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
    }
}
