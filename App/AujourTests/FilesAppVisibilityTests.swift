import Foundation
import Testing
@testable import Aujour

// Three Info.plist keys are the whole difference between a journal the user
// owns and app storage they cannot see (ADR 0001). None of them shows up in
// code, and a missing one fails silently — the app runs, writes entries, and
// the folder simply never appears in the Files app. So they are asserted here,
// against the bundle the tests are hosted in, which is the built app itself.
@Suite("The journal folder belongs to the user")
struct FilesAppVisibilityTests {
    @Test("the folder on this device shows up under On My iPhone")
    func theOnDeviceFolderIsPublished() {
        // `INFOPLIST_KEY_UIFileSharingEnabled` is silently ignored as a build
        // setting, which is how this went missing once already.
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool == true)
        #expect(
            Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool
                == true
        )
    }

    @Test("Aujour's iCloud Drive folder shows up under its own name, subfolders and all")
    func theICloudFolderIsPublished() throws {
        let containers = try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSUbiquitousContainers")
                as? [String: [String: Any]]
        )
        // The same container the locator asks iCloud for: this is where a
        // rename that only reached half the places would show up.
        let container = try #require(containers[JournalRootLocator.iCloudContainerIdentifier])

        #expect(container["NSUbiquitousContainerIsDocumentScopePublic"] as? Bool == true)
        // Entries live at YYYY/MM/YYYY-MM-DD.md, so a single level is not
        // enough for the Files app to show the journal as the user wrote it.
        #expect(container["NSUbiquitousContainerSupportedFolderLevels"] as? String == "Any")
        #expect(container["NSUbiquitousContainerName"] as? String == "Aujour")
    }

    @Test("the entitlements claim the very container the app asks iCloud for")
    func theEntitlementsNameTheSameContainer() throws {
        // Read off disk, the way Core's file-system purity test reads Core's
        // sources: an unsigned simulator build carries no entitlements, and a
        // disagreement here is invisible until a signed build fails to install
        // — or worse, installs and finds no container.
        let entitlements = URL(filePath: #filePath)  // App/AujourTests/<this file>
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Aujour/Aujour.entitlements")
        let claimed = try #require(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: entitlements),
                format: nil
            ) as? [String: Any]
        )

        for key in [
            "com.apple.developer.icloud-container-identifiers",
            "com.apple.developer.ubiquity-container-identifiers",
        ] {
            #expect(
                claimed[key] as? [String] == [JournalRootLocator.iCloudContainerIdentifier],
                "\(key) does not name the container the app asks for"
            )
        }
        // Documents in the container, not a CloudKit database: the journal is
        // files (ADR 0001).
        #expect(claimed["com.apple.developer.icloud-services"] as? [String] == ["CloudDocuments"])
    }
}
