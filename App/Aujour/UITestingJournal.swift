import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
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
///   and every test of it would otherwise start by typing a template into the
///   settings screen — which is a test of that screen, and there is one.
/// - **A photograph.** The system photo picker is another process's screen,
///   and driving it is the one part of adding a photograph that a UI test
///   cannot do without becoming a test of that screen.
/// - **A day's calendar.** `{{events}}` and `{{reminders}}` read the device's
///   own, and a simulator's is empty, unaskable and not the test's to seed.
///   So the suite says what the day held, and everything after that point —
///   the resolving, the formatting, the spawn — is the app's own code. A
///   UI-test journal never reaches EventKit at all, which is also what keeps
///   a permission alert from another process out of the middle of a test.
/// - **A day's photographs.** The suggestions panel reads the device's photo
///   library, which in a simulator is empty and behind a system alert nothing
///   in the suite can answer. So the test says which days the camera has
///   something from, and everything after that — which of them belong to the
///   day on screen, the panel, the tap — is the app's own code.
/// - **A place to be.** The `{{location}}` widget reads where the device is,
///   which in a simulator is a coordinate somebody set in a menu and behind a
///   system alert nothing in the suite can answer. So the test says which
///   places are around, and everything after that — the offer, the picker,
///   the answer written into the file — is the app's own code.
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

    /// The markdown a Content Template file holds. Seeded into the folder as
    /// a file, and named by the settings — which is what a Content Template is
    /// (ADR 0005).
    static let contentTemplateKey = "AUJOUR_UITEST_CONTENT_TEMPLATE"

    /// Where that file is seeded, inside the test's own journal folder. The
    /// `templates/` folder an Obsidian vault already keeps them in, so a suite
    /// that lists the folder sees what a real one would.
    static let contentTemplateFile = "templates/Daily.md"

    /// What the day being spawned held, one item per line, as
    /// `HH:mm Title` — or just `Title` for one the day holds without an hour.
    /// Read for whichever day is spawned, so a backfill gets them too.
    static let eventsKey = "AUJOUR_UITEST_EVENTS"
    static let remindersKey = "AUJOUR_UITEST_REMINDERS"

    /// The places around the device, one per line as `Name` — or
    /// `Name | Region` for one whose row says where it is. In the order they
    /// are offered, which is nearest first: the widget offers the first and
    /// the rest are what tapping to change is for.
    static let placesKey = "AUJOUR_UITEST_PLACES"

    /// Where the location permission stands before the test starts, and what
    /// the user says if they are asked — `allowed`, which is the default and
    /// what leaves every other test free of it; `undecided` for somebody who
    /// says yes to the offer to look; `refuses` for somebody who says no to
    /// it; and `refused` for somebody who said no some launch ago.
    ///
    /// There is no reaching CoreLocation from a UI test: it would be a system
    /// alert in the middle of one, and a simulator is nowhere. So this stands
    /// in, and everything after the answer — the offer, the picker, the
    /// answer — is the app's own code.
    static let placesAccessKey = "AUJOUR_UITEST_PLACES_ACCESS"

    /// The name of a folder for "Use a custom folder…" to pick, in place of
    /// the Files picker.
    static let folderToPickKey = "AUJOUR_UITEST_FOLDER_TO_PICK"

    /// The markdown a template file holds, for "Choose a template file…" to
    /// pick in place of the Files picker — written *outside* the journal
    /// folder, which is the case the picker exists for (ADR 0005).
    static let templateToPickKey = "AUJOUR_UITEST_TEMPLATE_TO_PICK"

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

    /// The format of a photograph to hand the editor in place of the one the
    /// system picker would have come back with — `png`, `jpeg` or `heic`.
    static let photographKey = "AUJOUR_UITEST_PHOTO"

    /// The days the device's photo library holds a photograph from, one per
    /// line as `YYYY-MM-DD` — or `YYYY-MM-DD HH:mm` for one taken at an hour
    /// the test cares about. One photograph each, drawn rather than carried.
    ///
    /// Which photographs a day is offered is the whole of the suggestions
    /// panel, so a test says them by the day they were taken on: that is how
    /// "today's photographs" and "the photographs of a day filled in later"
    /// are two different claims rather than the same one twice.
    static let photoLibraryKey = "AUJOUR_UITEST_PHOTO_LIBRARY"

    /// Where the library permission stands before the test starts, and what
    /// the user says if they are asked — `allowed`, which is the default and
    /// what leaves every other test free of it; `undecided` for somebody who
    /// says yes to the offer to look; `refuses` for somebody who says no to
    /// it; and `refused` for somebody who said no some launch ago.
    ///
    /// There is no reaching the device's own library from a UI test: it would
    /// be a system alert in the middle of one, and a simulator's library is
    /// nobody's day. So this stands in, and everything after the answer — the
    /// panel, the day query, the tap — is the app's own code.
    static let photoLibraryAccessKey = "AUJOUR_UITEST_PHOTO_LIBRARY_ACCESS"

    @MainActor
    static func fromLaunchEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Journal? {
        guard let folder = environment[folderKey], isAFolderName(folder) else { return nil }

        let settings = settingsStore(for: folder)
        let root = documentsFolder(named: folder)
        if let contentTemplate = environment[contentTemplateKey] {
            seed(contentTemplate, at: contentTemplateFile, under: root)
            settings.update { $0.contentTemplateFile = contentTemplateFile }
        }

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
            // Under a key of this test's own, like the folder's bookmark and
            // for the same reason: a template one test picked must never be
            // the one the next test opens with.
            templateElsewhere: .stored(
                key: "\(BookmarkedTemplateFile.bookmarkKey).\(folder)"
            ),
            versions: environment[divergedVersionKey].map { written in
                AVersionFromAnotherDevice(
                    written,
                    of: root.appending(path: entryPath)
                )
            } ?? ICloudVersions(),
            dayData: dayData(from: environment),
            photoLibrary: ALibrarySeededByATest(environment),
            places: PlacesSeededByATest(environment)
        )
    }

    /// The day's items a test seeded, as the data placeholders will read them.
    ///
    /// Always built, even when the test seeded nothing: what a UI test must
    /// not have is the *device's* calendar, and an empty day of its own is how
    /// `{{events}}` renders empty without anybody being asked for a
    /// permission.
    private static func dayData(from environment: [String: String]) -> DayData {
        DayData([
            .events: ADaySeededByATest(environment[eventsKey]),
            .reminders: ADaySeededByATest(environment[remindersKey]),
        ])
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

    /// The template file a UI test means to pick, written if it is not there
    /// yet — or `nil`, which is everybody else, and which is what leaves the
    /// Files picker in charge.
    ///
    /// Written here for the reason the picked folder is made here: a file
    /// picked in the Files app always exists, and the runner's own files are
    /// not somewhere the app can read. It sits beside the test journals rather
    /// than in one, because a template outside the journal folder is the case
    /// a picker is needed for at all — one inside it is a path, and needs no
    /// bookmark.
    @MainActor
    static func templateToPick(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let markdown = environment[templateToPickKey] else { return nil }

        let file = documentsFolder(named: "Templates").appending(path: "Daily.md")
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data(markdown.utf8).write(to: file)
        return file
    }

    /// A photograph a UI test means to insert, in the format it asked for —
    /// or `nil`, which is everybody else, and which is what leaves the system
    /// picker in charge.
    ///
    /// Drawn here rather than carried in the test bundle for the reason the
    /// picked folder is made here: the runner's files are not the app's, and a
    /// photograph the app cannot read is not one it could have inserted.
    static func photographToInsert(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Data? {
        guard let format = environment[photographKey] else { return nil }
        let arrivingAs: UTType =
            switch format {
            case "png": .png
            case "heic": .heic
            default: .jpeg
            }
        return photograph(as: arrivingAs)
    }

    /// A photograph in one format, drawn rather than carried: a few hundred
    /// bytes of one colour, which is a photograph for every purpose a test has.
    ///
    /// Shared with `InsertedPhotographsTests`, which wants the same thing for
    /// the same reason — what matters about a test's photograph is only the
    /// format it arrives in.
    ///
    /// - Parameter orientation: the EXIF orientation to write, for a test about
    ///   what survives a conversion. Left out for a photograph with nothing to
    ///   say about itself.
    static func photograph(as type: UTType, orientation: Int? = nil) -> Data? {
        let size = CGSize(width: 40, height: 30)
        let drawn = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        guard let image = drawn.cgImage else { return nil }
        let encoded = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                encoded as CFMutableData, type.identifier as CFString, 1, nil
            )
        else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return encoded as Data
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

/// A day's events or reminders, said at launch instead of read from the
/// device.
///
/// Written as lines — `09:30 Standup`, or `Bank holiday` for something the day
/// holds without an hour — and dated onto whichever day is being spawned, so
/// one seeding serves today's Entry and a backfill alike.
private struct ADaySeededByATest: DayItemSource {
    let lines: [Substring]

    init(_ seeded: String?) {
        self.lines = (seeded ?? "").split(whereSeparator: \.isNewline)
    }

    func items(during day: DateInterval) async -> [DayItem] {
        lines.map { line in
            let clock = line.prefix(5)
            guard clock.count == 5, clock.dropFirst(2).first == ":",
                let hour = Int(clock.prefix(2)), let minute = Int(clock.suffix(2))
            else { return DayItem(title: String(line)) }
            return DayItem(
                title: String(line.dropFirst(5).drop(while: { $0 == " " })),
                time: day.start.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
            )
        }
    }
}

/// The device's photo library, said at launch instead of read.
///
/// Always built, even when the test seeded nothing — what a UI test must not
/// have is the *device's* library, and an empty one of its own is how the
/// suggestions panel is absent without anybody being asked for a permission.
///
/// A class, and unchecked, because being asked has to stick: the panel reads
/// where the permission stands again every time the app comes back to the
/// front, and a library that forgot it had been allowed would offer to look
/// all over again.
private final class ALibrarySeededByATest: PhotoLibrary, @unchecked Sendable {
    private let taken: [Date]
    private let permission = NSLock()
    private var standing: PhotoLibraryAccess

    /// What the user says when the alert that is not there comes up.
    private let whenAsked: PhotoLibraryAccess

    init(_ environment: [String: String]) {
        self.taken = Self.days(environment[UITestingJournal.photoLibraryKey])
        let seeded = environment[UITestingJournal.photoLibraryAccessKey]
        self.standing =
            switch seeded {
            case "undecided", "refuses": .undecided
            case "refused": .refused
            default: .allowed
            }
        self.whenAsked = seeded == "refuses" ? .refused : .allowed
    }

    var access: PhotoLibraryAccess {
        permission.withLock { standing }
    }

    /// What the user says, seeded — there is no system alert here to tap, and
    /// there is deliberately none: it belongs to another process, and driving
    /// it would make every test of this panel a test of that alert.
    func ask() async -> PhotoLibraryAccess {
        permission.withLock {
            if standing == .undecided { standing = whenAsked }
            return standing
        }
    }

    func photographs(during span: DateInterval) async -> [DayPhotograph] {
        guard access == .allowed else { return [] }
        return
            taken
            .filter { $0 >= span.start && $0 < span.end }
            .map { DayPhotograph(id: "seeded-\($0.timeIntervalSince1970)", takenAt: $0) }
    }

    func thumbnail(of photograph: DayPhotograph) async -> Data? {
        UITestingJournal.photograph(as: .jpeg)
    }

    func contents(of photograph: DayPhotograph) async -> Data? {
        UITestingJournal.photograph(as: .jpeg)
    }

    /// `2026-03-14`, or `2026-03-14 09:30` — and noon for one that says only
    /// which day, which is a photograph in the middle of it wherever the
    /// device is.
    private static func days(_ seeded: String?) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return (seeded ?? "").split(whereSeparator: \.isNewline).compactMap { line in
            let said = line.split(separator: " ", maxSplits: 1)
            let date = said[0].split(separator: "-").compactMap { Int($0) }
            guard date.count == 3 else { return nil }
            let clock = said.count > 1 ? said[1].split(separator: ":").compactMap { Int($0) } : []

            var components = DateComponents()
            components.year = date[0]
            components.month = date[1]
            components.day = date[2]
            components.hour = clock.count == 2 ? clock[0] : 12
            components.minute = clock.count == 2 ? clock[1] : 0
            return calendar.date(from: components)
        }
    }
}

/// The places around the device, said at launch instead of found.
///
/// Always built, even when the test seeded nothing — what a UI test must not
/// have is the *device's* location, and nowhere of its own is how the widget
/// offers nothing without anybody being asked for a permission.
///
/// A class, and unchecked, because being asked has to stick: a device that
/// forgot it had been allowed would offer to look all over again the next time
/// a widget was tapped.
private final class PlacesSeededByATest: Places, @unchecked Sendable {
    private let around: Surroundings
    private let permission = NSLock()
    private var standing: PlaceAccess

    /// What the user says when the alert that is not there comes up.
    private let whenAsked: PlaceAccess

    init(_ environment: [String: String]) {
        self.around = Self.surroundings(environment[UITestingJournal.placesKey])
        let seeded = environment[UITestingJournal.placesAccessKey]
        self.standing =
            switch seeded {
            case "undecided", "refuses": .undecided
            case "refused": .refused
            default: .allowed
            }
        self.whenAsked = seeded == "refuses" ? .refused : .allowed
    }

    var access: PlaceAccess {
        permission.withLock { standing }
    }

    /// What the user says, seeded — there is no system alert here to tap, and
    /// there is deliberately none: it belongs to another process, and driving
    /// it would make every test of this widget a test of that alert.
    func ask() async -> PlaceAccess {
        permission.withLock {
            if standing == .undecided { standing = whenAsked }
            return standing
        }
    }

    func around() async -> Surroundings {
        guard access == .allowed else { return Surroundings() }
        return around
    }

    /// `Café de Flore`, or `Café de Flore | Paris` for one whose row says
    /// where it is. In the order they were written, which is the order they
    /// are offered in.
    ///
    /// All of them named places the device is standing in, and no area at all:
    /// which of the two leads the offer is
    /// `AujourCore.Surroundings.toOffer`'s, decided in metres and tested
    /// there. What a seeded launch is for is everything after that — the
    /// sheet, the picker, the answer reaching the file.
    private static func surroundings(_ seeded: String?) -> Surroundings {
        Surroundings(
            named: (seeded ?? "").split(whereSeparator: \.isNewline).enumerated()
                .compactMap { at, line in
                    let said = line.split(separator: "|", maxSplits: 1).map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    guard let name = said.first, !name.isEmpty else { return nil }
                    return NearbyPlace(
                        place: Place(
                            id: "seeded-\(at)",
                            name: name,
                            region: said.count > 1 && !said[1].isEmpty ? said[1] : nil
                        ),
                        metresAway: 0
                    )
                }
        )
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
