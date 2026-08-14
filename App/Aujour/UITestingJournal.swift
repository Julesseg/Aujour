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
/// - **A day two devices wrote.** An unresolved iCloud conflict takes two
///   devices, a sync and a moment of bad luck; there is no making one in a
///   simulator, and no waiting for one either. So the suite says what iCloud
///   would have been holding, and everything after that point — the policy,
///   the parking, the notice — is the app's own code over its own folder.
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

    /// What today's Entry file already says — a day this device wrote an hour
    /// ago, put there before the app opens the folder.
    static let todaysEntryKey = "AUJOUR_UITEST_TODAYS_ENTRY"

    /// What another device wrote for today, which iCloud is holding as a
    /// version of its own. Dated now, so it is the newer of the two.
    static let divergedVersionKey = "AUJOUR_UITEST_DIVERGED_VERSION"

    /// A file the folder already holds that is none of Aujour's business —
    /// a note the vault made — as a path relative to the Journal Root, and
    /// what it says.
    ///
    /// For the migration collision, which is a note already sitting where a
    /// new Path Template would put a day (ADR 0002). It is seeded rather than
    /// written by the app because that is what it is: somebody else's file,
    /// there before Aujour looked.
    static let vaultNotePathKey = "AUJOUR_UITEST_VAULT_NOTE_AT"
    static let vaultNoteKey = "AUJOUR_UITEST_VAULT_NOTE"

    @MainActor
    static func fromLaunchEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Journal? {
        guard let folder = environment[folderKey], isAFolderName(folder) else { return nil }

        let settings = settingsStore(for: folder)
        if let contentTemplate = environment[contentTemplateKey] {
            settings.update { $0.contentTemplate = contentTemplate }
        }

        let root = documentsFolder(named: folder)
        let entryPath = todaysEntryPath(rolloverHour: settings.settings.rolloverHour)
        if let written = environment[todaysEntryKey] {
            seed(written, at: entryPath, under: root)
        }
        if let note = environment[vaultNoteKey],
            let path = environment[vaultNotePathKey],
            (try? RelativePath(path)) != nil
        {
            seed(note, at: path, under: root)
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
            settings: settings,
            versions: environment[divergedVersionKey].map { written in
                AVersionFromAnotherDevice(
                    written,
                    of: root.appending(path: entryPath)
                )
            } ?? ICloudVersions()
        )
    }

    /// The journal-shaping settings for one test, kept apart from every other
    /// test's and from the app's own.
    ///
    /// Scoped rather than shared for the reason the journal folder is: a Path
    /// Template one test changes must not be the template the next test opens
    /// with, or "these entries are where the new template says" stops being a
    /// claim any test can make. Kept in a `UserDefaults` suite of the test's
    /// own — which is durable, so a change made in one launch is still there
    /// in the next, exactly as it is for a real install — and deliberately
    /// nowhere near iCloud, whose key-value storage is one bag per app and
    /// would carry one test's settings into the next.
    @MainActor
    private static func settingsStore(for folder: String) -> JournalSettingsStore {
        JournalSettingsStore(
            syncedThrough: SyncedSettingsStorage(
                iCloud: nil,
                onThisDevice: UserDefaults(suiteName: "aujour.uitest.\(folder)") ?? .standard
            )
        )
    }

    /// Where today's Entry belongs, so that the file seeded here is the one the
    /// app opens.
    ///
    /// Under the default Path Template, flatly: what a test seeds is seeded
    /// before the app opens, which is before any template it goes on to change
    /// has been changed. A second way of working the path out would be a
    /// second thing to be wrong about it.
    private static func todaysEntryPath(rolloverHour: RolloverHour) -> String {
        PathTemplate.default.render(
            JournalDay.current(at: Date(), in: .current, rolloverHour: rolloverHour)
        )
    }

    /// Writes a file into the journal folder as another app would have, before
    /// Aujour opens it — and dated an hour ago, because a divergence is decided
    /// by which version was written last and a file written this instant would
    /// tie with the version arriving.
    private static func seed(_ text: String, at relativePath: String, under root: URL) {
        let file = root.appending(path: relativePath)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data(text.utf8).write(to: file)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: file.path
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

/// The version of one file that iCloud would have been holding, said at launch
/// instead of arriving from another device.
///
/// It stands in for `NSFileVersion` and for nothing else: everything the app
/// does with it — weighing the two dates, giving the loser a file of its own,
/// telling the user — is the same code that runs over a real conflict. What
/// cannot be had in a simulator is the conflict itself.
///
/// A class, and unchecked, because settling it has to stick: a version still
/// reported after it has been parked would be parked again at every change in
/// the folder, which is exactly the failure the real one is guarded against.
///
/// Both halves of the seam at once — the versions held for a file, and the one
/// version — because here there is exactly one of each. Two objects to say
/// that would be two objects to keep in step.
private final class AVersionFromAnotherDevice: EntryVersions, EntryVersion, @unchecked Sendable {
    private let text: String
    private let file: URL
    private let settled = NSLock()
    private var isSettled = false

    /// Now, so that it is newer than the seeded Entry beside it and takes the
    /// day's path — the harder half of the decision to show.
    let writtenAt: Date? = Date()

    init(_ text: String, of file: URL) {
        self.text = text
        self.file = file.standardizedFileURL
    }

    func unresolved(at url: URL) -> [any EntryVersion] {
        settled.lock()
        defer { settled.unlock() }
        guard !isSettled, url.standardizedFileURL == file else { return [] }
        return [self]
    }

    func contents() throws -> Data {
        Data(text.utf8)
    }

    func settle() {
        settled.lock()
        isSettled = true
        settled.unlock()
    }
}
