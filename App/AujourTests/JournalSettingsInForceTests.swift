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
// and until there is a settings screen it is the only way one is set at all.

@MainActor
@Suite("The settings the journal is running on")
struct JournalSettingsInForceTests {
    @Test("today is spawned from the Content Template the iPad set")
    func todayIsSpawnedFromTheTemplateInForce() async throws {
        try await withTemporaryFolder { folders in
            try await withADeviceOfItsOwn { onThisDevice in
                let iCloud = AnICloudThatAnswers()
                iCloud.stored["aujour.journal.contentTemplate"] = "## Morning\n\n## Evening\n"

                let iCloudDocuments = folders.appending(
                    path: "iCloud/Documents",
                    directoryHint: .isDirectory
                )
                let journal = Journal(
                    locator: .test(iCloudDocuments: iCloudDocuments, folders: folders),
                    settings: JournalSettingsStore(
                        syncedThrough: SyncedSettingsStorage(
                            iCloud: iCloud,
                            onThisDevice: onThisDevice
                        )
                    )
                )
                await journal.open()

                // The blank page the app had before anything read the seam
                // would be `""` here.
                #expect(journal.today?.content == "## Morning\n\n## Evening\n")
            }
        }
    }

    @Test("today is the day the Rollover Hour says, not the calendar date")
    func todayIsResolvedByTheRolloverHourInForce() async throws {
        try await withTemporaryFolder { folders in
            try await withADeviceOfItsOwn { onThisDevice in
                // 11 at night: for every hour of the day but that one, the
                // Journal Day is still yesterday's date — so this is a claim
                // about the setting and not about the clock.
                let lateRollover = try #require(RolloverHour(hour: 23))
                let iCloud = AnICloudThatAnswers()
                iCloud.stored["aujour.journal.rolloverHour"] = "23"

                let iCloudDocuments = folders.appending(
                    path: "iCloud/Documents",
                    directoryHint: .isDirectory
                )
                let journal = Journal(
                    locator: .test(iCloudDocuments: iCloudDocuments, folders: folders),
                    settings: JournalSettingsStore(
                        syncedThrough: SyncedSettingsStorage(
                            iCloud: iCloud,
                            onThisDevice: onThisDevice
                        )
                    )
                )
                await journal.open()

                let now = Date()
                #expect(
                    journal.today?.day
                        == JournalDay.current(at: now, in: .current, rolloverHour: lateRollover)
                )
                // And the file it saves into is that day's, which is what
                // makes the setting worth having: words written at 1 AM go to
                // the day being described.
                let today = try #require(journal.today)
                today.content = "Still Tuesday, as far as this journal is concerned.\n"
                await today.save()

                let written = try String(
                    contentsOf: iCloudDocuments.appending(
                        path: PathTemplate.default.render(today.day)
                    ),
                    encoding: .utf8
                )
                #expect(written == "Still Tuesday, as far as this journal is concerned.\n")
            }
        }
    }

    @Test("no journal-shaping setting is ever written into the journal folder")
    func settingsNeverReachTheJournalRoot() async throws {
        try await withTemporaryFolder { folders in
            try await withADeviceOfItsOwn { onThisDevice in
                let iCloud = AnICloudThatAnswers()
                let iCloudDocuments = folders.appending(
                    path: "iCloud/Documents",
                    directoryHint: .isDirectory
                )
                let settings = JournalSettingsStore(
                    syncedThrough: SyncedSettingsStorage(
                        iCloud: iCloud,
                        onThisDevice: onThisDevice
                    )
                )
                let journal = Journal(
                    locator: .test(iCloudDocuments: iCloudDocuments, folders: folders),
                    settings: settings
                )
                await journal.open()

                settings.update {
                    $0.pathTemplate = "[Journal]/YYYY-MM-DD"
                    $0.contentTemplate = "## Morning\n"
                    $0.attachmentPathTemplate = "[assets]/YYYY"
                    $0.embedSyntax = .obsidianWikiLink
                    $0.rolloverHour = RolloverHour(hour: 4)!
                }

                // The folder is somebody's Obsidian vault: it holds Entries,
                // Attachments and Parked Files, and no configuration of
                // Aujour's, ever (ADR 0003). Nothing has been typed, so the
                // whole of what settings put in the folder is what is here.
                let inTheFolder = try FileManager.default.contentsOfDirectory(
                    at: iCloudDocuments,
                    includingPropertiesForKeys: nil
                )
                #expect(inTheFolder.isEmpty, "the folder holds \(inTheFolder.map(\.lastPathComponent))")
                // They went somewhere — this is not a test that passes because
                // nothing was written at all.
                #expect(iCloud.stored["aujour.journal.contentTemplate"] == "## Morning\n")
            }
        }
    }
}
