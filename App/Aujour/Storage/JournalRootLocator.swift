import Foundation

/// The folder the Journal lives in, and which of the two places it is.
///
/// Where it is matters to the user, not to the domain: everything above the
/// seam sees a Journal Store and nothing else. It is here because the app has
/// to be able to *say* where their words are being kept — a journal is a thing
/// people need to be able to find without the app's help (ADR 0001).
struct JournalRoot: Equatable, Sendable {
    let url: URL
    let location: Location

    enum Location: Equatable, Sendable {
        /// A folder Aujour found for itself, which is the whole of "a fresh
        /// install just works" (ADR 0004).
        case aujoursOwn(DefaultFolder)

        /// A folder the user pointed Aujour at in the Files app — typically
        /// inside an Obsidian vault, so that daily notes and Entries are the
        /// same files.
        ///
        /// Named rather than pathed, because the name is what the user picked
        /// and what they would recognize; where it sits in the Files app is
        /// not something a security-scoped folder can be asked.
        case customFolder(name: String)
    }

    /// Which of the two folders Aujour can find on its own a journal lives in.
    ///
    /// Settled on the first launch and then remembered on the device, because
    /// a journal that moved between them on its own would be a journal with
    /// holes in it (ADR 0004).
    enum DefaultFolder: String, Equatable, Sendable {
        /// Aujour's own folder in iCloud Drive: visible in the Files app,
        /// synced between the user's devices, and still there after the app
        /// is deleted.
        case iCloudDrive

        /// The app's own Documents folder, visible in the Files app under
        /// "On My iPhone". Where a journal starts when iCloud Drive is off —
        /// it goes with the app if the app goes, which is why it is second
        /// choice and why the app says so.
        case onThisDevice
    }
}

/// Finds the folder to journal into: the one the user pointed Aujour at, or —
/// until they point it anywhere — the one Aujour finds for itself, which is
/// the whole of "a fresh install just works".
///
/// It has one rule beyond preferring iCloud Drive: **a journal does not move
/// on its own.** The first launch settles the question and the answer is
/// remembered on the device, because the alternative is a journal split in
/// two — an entry written in an airport with iCloud off, then never seen
/// again once iCloud comes back. So a journal that started on the device
/// stays on the device, and a journal that lives in iCloud is never quietly
/// re-homed: if iCloud is away, that is a failure with a sentence for the
/// user (ADR 0001 — the folder is the journal, and the app does not get to
/// substitute a different one).
///
/// A chosen folder is held to the same rule, and it is the reason the rule is
/// stated once here rather than at each branch: a vault folder that has been
/// renamed away is a failure the user is shown, never a quiet return to
/// Aujour's own folder, where the Entries they can see in Obsidian would
/// simply not be.
///
/// The ways it reaches the world are injected so that every branch, and every
/// failure, is tested against real folders rather than against the device the
/// test happens to run on.
struct JournalRootLocator: Sendable {
    var iCloudDocuments: @Sendable () -> URL?
    var onThisDeviceDocuments: @Sendable () -> URL
    var lastUsedLocation: @Sendable () -> JournalRoot.DefaultFolder?
    var rememberLocation: @Sendable (JournalRoot.DefaultFolder) -> Void

    /// The folder the user pointed Aujour at, if they have — and the way they
    /// point it somewhere else or come back.
    var chosenFolder: ChosenJournalFolder = .unchosen

    func locate() throws -> JournalRoot {
        // A journal that has been pointed somewhere is not one to go looking
        // for, so this answers on its own — including by failing.
        if let chosen = try chosenFolder.resolve() {
            return JournalRoot(
                url: chosen,
                location: .customFolder(name: chosen.lastPathComponent)
            )
        }

        // Where this journal already lives is the whole answer; the only
        // question left is whether it is reachable, and if not that is a
        // failure rather than a different folder.
        if let settled = lastUsedLocation() {
            guard let url = folder(for: settled) else {
                throw JournalRootError.journalRootUnavailable
            }
            return JournalRoot(url: url, location: .aujoursOwn(settled))
        }

        // Nothing settled yet, so this is a first launch: iCloud Drive if it
        // will have us, the device if not.
        for location in [JournalRoot.DefaultFolder.iCloudDrive, .onThisDevice] {
            guard let url = folder(for: location) else { continue }
            rememberLocation(location)
            return JournalRoot(url: url, location: .aujoursOwn(location))
        }
        throw JournalRootError.journalRootUnavailable
    }

    /// The folder for one of Aujour's own locations, made if it is not there
    /// yet — and `nil` if it cannot be one, which for iCloud Drive means it is
    /// off or has not arrived on this device yet.
    private func folder(for location: JournalRoot.DefaultFolder) -> URL? {
        let url =
            switch location {
            case .iCloudDrive: iCloudDocuments()
            case .onThisDevice: onThisDeviceDocuments()
            }
        guard let url else { return nil }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url.standardizedFileURL
        } catch {
            return nil
        }
    }
}

extension JournalRootLocator {
    /// Aujour's iCloud container, named the way Apple requires: `iCloud.` and
    /// the app's own bundle identifier.
    ///
    /// The entitlements and the `NSUbiquitousContainers` Info.plist entry
    /// spell the same identifier out — Apple's tooling reads both as literals,
    /// so they cannot derive it. All three have to agree or the folder never
    /// appears, silently, which is why a test holds them to it
    /// (`FilesAppVisibilityTests`).
    static var iCloudContainerIdentifier: String {
        "iCloud.\(Bundle.main.bundleIdentifier ?? "")"
    }

    private static let lastUsedLocationKey = "JournalRootLocation"

    /// The locator over this device: Aujour's iCloud Drive folder, the app's
    /// own Documents folder, and a device-local memory of which one this
    /// journal uses (per-device by nature, so it never travels through the
    /// synced settings seam — ADR 0003).
    static var system: JournalRootLocator {
        JournalRootLocator(
            iCloudDocuments: {
                // Blocking, and slow the first time — the caller keeps this
                // off the main actor.
                FileManager.default
                    .url(forUbiquityContainerIdentifier: iCloudContainerIdentifier)?
                    // The container's `Documents` folder is the part iCloud
                    // Drive shows in the Files app; everything beside it is
                    // private to the app.
                    .appending(path: "Documents", directoryHint: .isDirectory)
            },
            onThisDeviceDocuments: {
                URL.documentsDirectory
            },
            lastUsedLocation: {
                UserDefaults.standard.string(forKey: lastUsedLocationKey)
                    .flatMap(JournalRoot.DefaultFolder.init(rawValue:))
            },
            rememberLocation: { location in
                UserDefaults.standard.set(location.rawValue, forKey: lastUsedLocationKey)
            },
            chosenFolder: .stored()
        )
    }
}
