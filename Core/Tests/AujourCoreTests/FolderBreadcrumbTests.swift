import Foundation
import Testing

@testable import AujourCore

// Where a picked folder sits, said the way the Files app said it on the way
// to picking it — and only where the path can honestly say.

@Suite("Naming where a picked folder sits")
struct FolderBreadcrumbTests {
    private let obsidianVault =
        "/private/var/mobile/Library/Mobile Documents/iCloud~md~obsidian/Documents/Vault/Journal"

    @Test("a folder in an app's iCloud container is under iCloud Drive and the app")
    func insideAnAppsContainer() {
        let breadcrumb = FolderBreadcrumb(folderPath: obsidianVault)
        #expect(breadcrumb.crumbs == ["iCloud Drive", "Obsidian", "Vault", "Journal"])
        #expect(breadcrumb.description == "iCloud Drive › Obsidian › Vault › Journal")
    }

    @Test("the container's Documents folder is the app's own crumb, not one of its own")
    func theDocumentsFolderIsTheApp() {
        let documents = "/private/var/mobile/Library/Mobile Documents/iCloud~md~obsidian/Documents"
        #expect(FolderBreadcrumb(folderPath: documents).crumbs == ["iCloud Drive", "Obsidian"])
    }

    @Test("a folder at the top of iCloud Drive is under iCloud Drive alone")
    func atTheTopOfICloudDrive() {
        let loose = "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Notes/Journal"
        #expect(FolderBreadcrumb(folderPath: loose).crumbs == ["iCloud Drive", "Notes", "Journal"])
    }

    @Test("the app's crumb is the last word of its container, with a capital")
    func theAppsName() {
        let aujour = "/x/Mobile Documents/iCloud~com~julesseguin~aujour/Documents/Journal"
        #expect(FolderBreadcrumb(folderPath: aujour).crumbs == ["iCloud Drive", "Aujour", "Journal"])
    }

    @Test("a trailing slash is not a crumb")
    func trailingSlash() {
        #expect(
            FolderBreadcrumb(folderPath: obsidianVault + "/").crumbs
                == ["iCloud Drive", "Obsidian", "Vault", "Journal"]
        )
    }

    // Another app's "On My iPhone" folder: the app's name is not in the
    // path, and a breadcrumb that left it out would point somewhere that is
    // not there.
    @Test("a folder anywhere else is its own name and nothing more")
    func anywhereElse() {
        let onDevice = "/private/var/mobile/Containers/Data/Application/8C2F7DE0/Documents/Journal"
        #expect(FolderBreadcrumb(folderPath: onDevice).crumbs == ["Journal"])

        let provider = "/private/var/mobile/Containers/Shared/AppGroup/1A2B/File Provider Storage/Journal"
        #expect(FolderBreadcrumb(folderPath: provider).crumbs == ["Journal"])

        let temporary = "/var/folders/xy/T/Obsidian/Journal"
        #expect(FolderBreadcrumb(folderPath: temporary).description == "Journal")
    }

    @Test("a container that is not an app's is not guessed at")
    func anUnknownContainer() {
        let odd = "/x/Mobile Documents/something~else/Documents/Journal"
        #expect(FolderBreadcrumb(folderPath: odd).crumbs == ["Journal"])
    }

    @Test("crumbs given directly are shown as given")
    func givenDirectly() {
        #expect(FolderBreadcrumb(crumbs: ["Journal"]).description == "Journal")
        #expect(FolderBreadcrumb(crumbs: []).description == "")
    }
}
