import Foundation
import Testing
import AujourCore
@testable import Aujour

// The first thing that happens on a fresh install: with nothing configured
// and nobody asked anything, Aujour has to arrive at a folder it can journal
// into — and then keep arriving at the *same* one, because a journal split
// across two folders is a journal with holes in it.
@Suite("Finding the default Journal Root")
struct JournalRootLocatorTests {
    /// What the device would have remembered. A reference so the locator's
    /// `@Sendable` closure can write to it; unchecked because `locate()` is
    /// synchronous and nothing here is concurrent.
    final class Remembered: @unchecked Sendable {
        var location: JournalRoot.DefaultFolder?
    }

    @Test("a fresh install lands in iCloud Drive, and the folder is made for it")
    func aFreshInstallJournalsIntoICloudDrive() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let remembered = Remembered()
            let locator = JournalRootLocator(
                iCloudDocuments: { iCloud },
                onThisDeviceDocuments: { folders.appending(path: "Device") },
                lastUsedLocation: { nil },
                rememberLocation: { remembered.location = $0 }
            )

            let root = try locator.locate()

            #expect(root.location == .aujoursOwn(.iCloudDrive))
            #expect(root.url == iCloud.standardizedFileURL)
            #expect(FileManager.default.fileExists(atPath: iCloud.path))
            #expect(remembered.location == .iCloudDrive)
        }
    }

    @Test("without iCloud, a fresh install journals on the device rather than refusing to start")
    func withoutICloudAFreshInstallJournalsOnTheDevice() async throws {
        try await withTemporaryFolder { folders in
            let device = folders.appending(path: "Device/Documents", directoryHint: .isDirectory)
            let remembered = Remembered()
            let locator = JournalRootLocator(
                iCloudDocuments: { nil },
                onThisDeviceDocuments: { device },
                lastUsedLocation: { nil },
                rememberLocation: { remembered.location = $0 }
            )

            let root = try locator.locate()

            #expect(root.location == .aujoursOwn(.onThisDevice))
            #expect(root.url == device.standardizedFileURL)
            #expect(FileManager.default.fileExists(atPath: device.path))
            #expect(remembered.location == .onThisDevice)
        }
    }

    @Test("a journal that started on the device stays there, even once iCloud shows up")
    func aDeviceJournalIsNotAbandonedWhenICloudArrives() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            let device = folders.appending(path: "Device/Documents", directoryHint: .isDirectory)
            try device.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            let locator = JournalRootLocator(
                iCloudDocuments: { iCloud },
                onThisDeviceDocuments: { device },
                lastUsedLocation: { .onThisDevice },
                rememberLocation: { _ in }
            )

            let root = try locator.locate()

            // Switching would leave every entry written so far invisible.
            #expect(root.location == .aujoursOwn(.onThisDevice))
            #expect(root.url == device.standardizedFileURL)
        }
    }

    @Test("a journal that lives in iCloud is never quietly re-homed when iCloud is away")
    func anICloudJournalFailsRatherThanSilentlyMovingToTheDevice() async throws {
        try await withTemporaryFolder { folders in
            let locator = JournalRootLocator(
                iCloudDocuments: { nil },
                onThisDeviceDocuments: { folders.appending(path: "Device") },
                lastUsedLocation: { .iCloudDrive },
                rememberLocation: { _ in }
            )

            // Signed out of iCloud, today's entry would go somewhere the rest
            // of the journal is not. Better to say so.
            #expect(throws: JournalRootError.journalRootUnavailable) {
                try locator.locate()
            }
        }
    }

    @Test("finding the root again leaves what is already in it alone")
    func locatingAnExistingRootKeepsItsContents() async throws {
        try await withTemporaryFolder { folders in
            let iCloud = folders.appending(path: "iCloud/Documents", directoryHint: .isDirectory)
            try iCloud.seed("Walked to the market.\n", at: "2026/03/2026-03-01.md")
            let locator = JournalRootLocator(
                iCloudDocuments: { iCloud },
                onThisDeviceDocuments: { folders.appending(path: "Device") },
                lastUsedLocation: { .iCloudDrive },
                rememberLocation: { _ in }
            )

            let root = try locator.locate()
            let store: any JournalStore = FileJournalStore(root: root.url)

            #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
        }
    }

    @Test("a fresh install falls back to the device when the iCloud folder cannot be made")
    func anUnusableICloudFolderIsNotICloudAtAll() async throws {
        try await withTemporaryFolder { folders in
            // Something is already at the path the folder would take, so it
            // can never be a folder — as good as iCloud not being there.
            try folders.seed("in the way", at: "iCloud")
            let device = folders.appending(path: "Device/Documents", directoryHint: .isDirectory)
            let locator = JournalRootLocator(
                iCloudDocuments: { folders.appending(path: "iCloud/Documents") },
                onThisDeviceDocuments: { device },
                lastUsedLocation: { nil },
                rememberLocation: { _ in }
            )

            let root = try locator.locate()

            #expect(root.location == .aujoursOwn(.onThisDevice))
            #expect(FileManager.default.fileExists(atPath: device.path))
        }
    }

    @Test("with nowhere at all to write, the failure is one the user can be shown")
    func nowhereToWriteIsAPresentableFailure() async throws {
        try await withTemporaryFolder { folders in
            try folders.seed("in the way", at: "Device")
            let locator = JournalRootLocator(
                iCloudDocuments: { nil },
                onThisDeviceDocuments: { folders.appending(path: "Device/Documents") },
                lastUsedLocation: { nil },
                rememberLocation: { _ in }
            )

            #expect(throws: JournalRootError.journalRootUnavailable) {
                try locator.locate()
            }
        }
    }

    @Test("the system locator asks iCloud for Aujour's own container")
    func theSystemLocatorUsesAujoursOwnICloudContainer() {
        // The container the entitlements name, derived rather than spelled out
        // twice: `iCloud.` + the app's bundle identifier.
        #expect(JournalRootLocator.iCloudContainerIdentifier == "iCloud.com.julesseguin.aujour")
    }
}
