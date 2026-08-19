import Foundation
import Testing
import AujourCore

@testable import Aujour

// The settings the app is actually running on, over a real folder. What a
// Content Template renders to and which day a Rollover Hour makes it is
// arithmetic, and lives in Core; what is left here is the wiring — that the
// values the app spawns and saves today's Entry by are the ones in the seam,
// and not the defaults it would have used if nothing were reading them.
//
// "Set on another device" is where the values come from throughout: iCloud is
// the only way a journal-shaping setting reaches a second device (ADR 0003),
// so this is the arriving half. The half where somebody sets one here is the
// journal sheet, and `JournalSettingsChangeTests`.

@MainActor
@Suite("The settings the journal is running on")
struct JournalSettingsInForceTests {
    @Test("today is spawned from the Content Template file the iPad set")
    func todayIsSpawnedFromTheTemplateInForce() async throws {
        try await withAJournalShapedBy(
            ["aujour.journal.contentTemplateFile": "templates/Daily.md"]
        ) { aujour in
            // The file the setting names, in the folder both devices share —
            // which is the whole of why the setting is a path (ADR 0005).
            try aujour.root.seed("## Morning\n\n## Evening\n", at: "templates/Daily.md")
            await aujour.journal.open()

            // The blank page the app had before anything read the seam would
            // be `""` here.
            #expect(aujour.journal.today?.content == "## Morning\n\n## Evening\n")
        }
    }

    @Test("today is the day the Rollover Hour says, not the calendar date")
    func todayIsResolvedByTheRolloverHourInForce() async throws {
        // 11 at night: for every hour of the day but that one, the Journal Day
        // is still yesterday's date — so this is a claim about the setting and
        // not about the clock.
        let lateRollover = try #require(RolloverHour(hour: 23))
        try await withAJournalShapedBy(["aujour.journal.rolloverHour": "23"]) { aujour in
            await aujour.journal.open()

            #expect(
                aujour.journal.today?.day
                    == JournalDay.current(at: Date(), in: .current, rolloverHour: lateRollover)
            )
            // And the file it saves into is that day's, which is what makes
            // the setting worth having: words written at 1 AM go to the day
            // being described.
            let today = try #require(aujour.journal.today)
            today.content = "Still Tuesday, as far as this journal is concerned.\n"
            await today.save()

            let written = try String(
                contentsOf: aujour.root.appending(path: PathTemplate.default.render(today.day)),
                encoding: .utf8
            )
            #expect(written == "Still Tuesday, as far as this journal is concerned.\n")
        }
    }

    @Test("no journal-shaping setting is ever written into the journal folder")
    func settingsNeverReachTheJournalRoot() async throws {
        try await withAJournalShapedBy([:]) { aujour in
            await aujour.journal.open()

            aujour.settings.update {
                $0.pathTemplate = "[Journal]/YYYY-MM-DD"
                $0.contentTemplateFile = "templates/Daily.md"
                $0.attachmentPathTemplate = "[assets]/YYYY"
                $0.embedSyntax = .obsidianWikiLink
                $0.rolloverHour = RolloverHour(hour: 4)!
            }

            // The folder is somebody's Obsidian vault: it holds Entries,
            // Attachments and Parked Files, and no configuration of Aujour's,
            // ever (ADR 0003). Nothing has been typed, so the whole of what
            // settings put in the folder is what is here.
            let inTheFolder = try FileManager.default.contentsOfDirectory(
                at: aujour.root,
                includingPropertiesForKeys: nil
            )
            #expect(
                inTheFolder.isEmpty,
                "the folder holds \(inTheFolder.map(\.lastPathComponent))"
            )
            // They went somewhere — this is not a test that passes because
            // nothing was written at all.
            #expect(
                aujour.iCloud.stored["aujour.journal.contentTemplateFile"] == "templates/Daily.md"
            )
        }
    }

    /// A journal over a folder of its own, opened onto the settings another
    /// device left in iCloud before this one ever launched — which is the only
    /// way a journal-shaping setting is set at all until there is a screen for
    /// it, and so the way these are all put.
    private func withAJournalShapedBy(
        _ whatTheOtherDeviceLeft: [String: String],
        _ body: (AujourOverAFolder) async throws -> Void
    ) async throws {
        try await withTemporaryFolder { folders in
            try await withADeviceOfItsOwn { onThisDevice in
                let iCloud = AnICloudThatAnswers()
                iCloud.stored = whatTheOtherDeviceLeft
                let root = folders.appending(
                    path: "iCloud/Documents",
                    directoryHint: .isDirectory
                )
                let settings = JournalSettingsStore(
                    syncedThrough: SyncedSettingsStorage(
                        iCloud: iCloud,
                        onThisDevice: onThisDevice
                    )
                )
                try await body(
                    AujourOverAFolder(
                        journal: Journal(
                            locator: .test(iCloudDocuments: root, folders: folders),
                            settings: settings
                        ),
                        settings: settings,
                        root: root,
                        iCloud: iCloud
                    )
                )
            }
        }
    }
}

/// One installation of Aujour as a test has it: the journal, the settings it
/// is running on, the folder its Entries land in, and the iCloud those
/// settings came from — which is where a test looks to say what travelled.
@MainActor
private struct AujourOverAFolder {
    let journal: Journal
    let settings: JournalSettingsStore
    let root: URL
    let iCloud: AnICloudThatAnswers
}
