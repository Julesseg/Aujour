import Foundation
import Testing
import AujourCore
@testable import Aujour

// What the app does before it shows anybody anything: find the folder, open a
// store over it, and end up in one of exactly two states — journaling, or
// saying why not.
@MainActor
@Suite("Opening the Journal on launch")
struct JournalStorageTests {
    @Test("a fresh install opens onto a real folder, with no configuration anywhere")
    func aFreshInstallOpensOntoARealFolder() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory(),
                templateElsewhere: .unpicked
            )

            await journal.open()

            #expect(journal.state == .open(JournalRoot(url: iCloud.standardizedFileURL, location: .aujoursOwn(.iCloudDrive)), entryCount: 0))
            #expect(journal.store != nil)

            // And it is a folder the app can actually journal into.
            try await #require(journal.store).writeText("First words.\n", at: "2026/03/2026-03-01.md")
            let onDisk = try String(
                contentsOf: iCloud.appending(path: "2026/03/2026-03-01.md"),
                encoding: .utf8
            )
            #expect(onDisk == "First words.\n")
        }
    }

    @Test("a folder that already holds a journal opens with it, not over it")
    func anExistingJournalIsFoundWhereItWasLeft() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            try iCloud.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            try iCloud.seed("February's last day.\n", at: "2026/02/2026-02-28.md")
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory(),
                templateElsewhere: .unpicked
            )

            await journal.open()

            #expect(journal.state == .open(JournalRoot(url: iCloud.standardizedFileURL, location: .aujoursOwn(.iCloudDrive)), entryCount: 2))
        }
    }

    @Test("opening the journal leaves today's Entry on screen, ready to type into")
    func openingLeavesTodaysEntryReady() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
            try iCloud.seed("Walked to the market.\n", at: PathTemplate.default.render(today))
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory(),
                templateElsewhere: .unpicked
            )

            await journal.open()

            let editor = try #require(journal.today)
            #expect(editor.day == today)
            #expect(editor.content == "Walked to the market.\n")
            #expect(editor.state.isEditing)
        }
    }

    @Test("the journal's calendar marks the days the folder actually holds")
    func theCalendarIsScannedFromTheSameFolder() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
            let earlier = today.adding(days: -2)
            try iCloud.seed("Rain all day.\n", at: PathTemplate.default.render(earlier))
            // Files that are not Entries, which no day is marked by.
            try iCloud.seed("Not an Entry.\n", at: "notes.md")
            try iCloud.seed("A parked divergence.\n", at: PathTemplate.default.render(earlier)
                .replacingOccurrences(of: ".md", with: "_1.md"))
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory(),
                templateElsewhere: .unpicked
            )

            await journal.open()
            let calendar = try #require(journal.calendar)
            await calendar.scan()
            // The month that day is in — a step back when the last two days
            // crossed the turn of a month.
            if earlier.month != today.month { calendar.showPreviousMonth() }

            #expect(calendar.problem == nil)
            #expect(calendar.month.days.filter(\.isJournaled).map(\.day) == [earlier])
            // And it is the way in to that day: what the calendar opens is
            // the Entry the folder holds.
            let editor = try #require(calendar.editor(for: earlier))
            await editor.open()
            #expect(editor.content == "Rain all day.\n")
        }
    }

    @Test("how much is in the folder is asked again, not remembered from launch")
    func recountingSeesWhatWasWrittenSince() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let root = JournalRoot(url: iCloud.standardizedFileURL, location: .aujoursOwn(.iCloudDrive))
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory(),
                templateElsewhere: .unpicked
            )
            await journal.open()
            #expect(journal.state == .open(root, entryCount: 0))

            // What today's first edit does, from the outside.
            try await #require(journal.store).writeText("First words.\n", at: "2026/03/2026-03-01.md")
            await journal.recount()

            #expect(journal.state == .open(root, entryCount: 1))
        }
    }

    @Test("a day edited outside Aujour turns up on screen, without anybody asking")
    func anEditMadeElsewhereReachesTodaysEntry() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
            let entry = PathTemplate.default.render(today)
            try iCloud.seed("Walked to the market.\n", at: entry)
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory(),
                templateElsewhere: .unpicked
            )

            await journal.open()
            let editor = try #require(journal.today)
            #expect(editor.content == "Walked to the market.\n")

            // Obsidian, saving today's note in the other half of the split
            // screen. Nothing in Aujour asks for this — the folder says so,
            // and the Entry on screen catches up because nothing is waiting to
            // be written to it.
            try iCloud.somebodyElseWrites(
                "Walked to the market, and back the long way.\n",
                at: entry
            )

            await expect(editor, toShow: "Walked to the market, and back the long way.\n")
        }
    }

    @Test("coming back to the front catches up with what happened while away")
    func comingBackToTheFrontReadsTheFolderAgain() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let today = JournalDay.current(at: .now, in: .current, rolloverHour: .midnight)
            let earlier = today.adding(days: -2)
            try iCloud.seed("Walked to the market.\n", at: PathTemplate.default.render(today))
            let journal = Journal(
                locator: .test(iCloudDocuments: iCloud, folders: folders),
                settings: .inMemory(),
                templateElsewhere: .unpicked
            )
            await journal.open()
            let calendar = try #require(journal.calendar)
            await calendar.scan()

            // Written while Aujour was in the background, which is where it is
            // told nothing at all: today's Entry edited, and an older day
            // filled in from the iPad.
            try iCloud.seed("Walked to the market, and back the long way.\n",
                at: PathTemplate.default.render(today))
            try iCloud.seed("Rain all day.\n", at: PathTemplate.default.render(earlier))

            await journal.cameBackToTheFront()

            #expect(journal.today?.content == "Walked to the market, and back the long way.\n")
            if earlier.month != today.month { calendar.showPreviousMonth() }
            #expect(calendar.month.days.filter(\.isJournaled).map(\.day).contains(earlier))
        }
    }

    @Test("a folder Aujour cannot reach becomes something to say, not an empty page")
    func anUnreachableFolderIsPresented() async throws {
        try await withTemporaryFolder { folders in
            try folders.seed("in the way", at: "Device")
            let journal = Journal(
                locator: JournalRootLocator(
                    iCloudDocuments: { nil },
                    onThisDeviceDocuments: { folders.appending(path: "Device/Documents") },
                    lastUsedLocation: { nil },
                    rememberLocation: { _ in }
                )
            )

            await journal.open()

            guard case .unavailable(let problem) = journal.state else {
                Issue.record("expected an unavailable journal, got \(journal.state)")
                return
            }
            #expect(problem.message.isEmpty == false)
            #expect(problem.suggestion.isEmpty == false)
            // Nothing to journal through: better than a store that silently
            // writes somewhere the rest of the journal is not.
            #expect(journal.store == nil)
            // And nothing to type into either — an editor over a folder that
            // is not there would take words it could never save, and a
            // calendar over it would mark no days at all, which is what an
            // empty journal looks like.
            #expect(journal.today == nil)
            #expect(journal.calendar == nil)
        }
    }

    @Test("every place the journal can live is described to the user")
    func everyLocationSaysWhatItMeansForTheirWords() {
        for location in [JournalRoot.Location.aujoursOwn(.iCloudDrive), .aujoursOwn(.onThisDevice), .customFolder(name: "Journal")] {
            #expect(location.name(onDevice: "iPhone").isEmpty == false)
            #expect(location.promise(onDevice: "iPhone").isEmpty == false)
            #expect(location.symbolName(onDevice: "iPhone").isEmpty == false)
        }
        // The one thing the on-device story has to be honest about.
        #expect(JournalRoot.Location.aujoursOwn(.onThisDevice).promise(onDevice: "iPhone").contains("iCloud Drive"))
    }

    @Test("the on-device folder is named after the device the app is actually on")
    func theOnDeviceFolderIsNamedAfterThisDevice() {
        // Aujour runs on iPhone and iPad, and the Files app calls the folder
        // "On My iPad" there — pointing an iPad user at "On My iPhone" sends
        // them somewhere that does not exist.
        let onIPad = JournalRoot.Location.aujoursOwn(.onThisDevice)
        #expect(onIPad.name(onDevice: "iPad") == "On My iPad › Aujour")
        #expect(onIPad.promise(onDevice: "iPad").contains("this iPad"))
        #expect(onIPad.symbolName(onDevice: "iPad") == "ipad")
        #expect(onIPad.symbolName(onDevice: "iPhone") == "iphone")

        // iCloud Drive is the same folder wherever you are looking from.
        #expect(
            JournalRoot.Location.aujoursOwn(.iCloudDrive).name(onDevice: "iPad")
                == JournalRoot.Location.aujoursOwn(.iCloudDrive).name(onDevice: "iPhone")
        )
    }
}

/// Waits for the Entry on screen to say something, up to a deadline.
///
/// Polled, because what is being waited for is the system telling a file
/// presenter about somebody else's write, and then a folder being read — the
/// one thing in these tests that happens on its own schedule rather than on
/// the test's. The deadline is generous for the same reason it is over in
/// `CoordinatedJournalRootTests`: it is there so that "never" is not
/// "forever", and says nothing about how fast a change ought to arrive.
@MainActor
private func expect(
    _ editor: EntryEditor,
    toShow text: String,
    within seconds: Double = 20,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline, editor.content != text {
        try? await Task.sleep(for: .milliseconds(50))
    }
    #expect(editor.content == text, sourceLocation: sourceLocation)
}

extension JournalRootLocator {
    /// A locator over folders a test owns, starting from nothing remembered.
    static func test(iCloudDocuments: URL, folders: URL) -> JournalRootLocator {
        JournalRootLocator(
            iCloudDocuments: { iCloudDocuments },
            onThisDeviceDocuments: { folders.appending(path: "Device/Documents") },
            lastUsedLocation: { nil },
            rememberLocation: { _ in }
        )
    }
}
