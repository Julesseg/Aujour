import Foundation

/// Where a folder sits, the way the Files app shows it: "iCloud Drive ›
/// Obsidian › Vault › Journal".
///
/// A folder the user picked comes back as a path, and a path is a sandbox
/// container's worth of hex ahead of the one word that matters. The Files app
/// showed them somewhere they recognised on the way to picking it, and this
/// reads that back off the path — for the one place whose layout is public,
/// which is iCloud Drive: every app's container sits under `Mobile Documents`
/// by identifier, and iCloud Drive's own top level is the `com~apple~CloudDocs`
/// container.
///
/// Anywhere else — another app's "On My iPhone" folder, a third-party
/// provider — the path says nothing the user would recognise, so the crumb is
/// the folder's own name and nothing more. Their own name for their own
/// folder is what they picked it by, and a guess at the rest would be a
/// breadcrumb to somewhere that is not there.
///
/// Read off strings, deliberately: nothing here asks the file system anything,
/// so it is tested against paths rather than against a device that has an
/// Obsidian on it.
public struct FolderBreadcrumb: Equatable, Sendable, CustomStringConvertible {
    /// What the Files app puts between crumbs.
    public static let separator = " › "

    /// The Files app's name for the root of iCloud Drive.
    public static let iCloudDrive = "iCloud Drive"

    /// From the place the user would look first to the folder itself.
    public let crumbs: [String]

    public init(crumbs: [String]) {
        self.crumbs = crumbs
    }

    /// The breadcrumb for a folder at this path.
    ///
    /// Under iCloud Drive it is the whole way down from "iCloud Drive"; the
    /// app's crumb is the container's own last word ("iCloud~md~obsidian" is
    /// Obsidian), which is the app's name in every case that matters and the
    /// closest the path comes to the name the Files app shows. Anywhere else
    /// it is the folder's own name.
    public init(folderPath path: String) {
        let components = path.split(separator: "/").map(String.init)
        if let inICloud = Self.crumbsInICloudDrive(components) {
            crumbs = inICloud
        } else {
            crumbs = components.last.map { [$0] } ?? []
        }
    }

    public var description: String { crumbs.joined(separator: Self.separator) }

    private static let mobileDocuments = "Mobile Documents"
    private static let iCloudDriveContainer = "com~apple~CloudDocs"

    /// The way down from iCloud Drive, or `nil` for a path that is not in it.
    private static func crumbsInICloudDrive(_ components: [String]) -> [String]? {
        guard let library = components.firstIndex(of: mobileDocuments),
            components.count > library + 1
        else { return nil }
        let container = components[library + 1]
        var below = Array(components[(library + 2)...])

        if container == iCloudDriveContainer {
            return [iCloudDrive] + below
        }
        guard container.hasPrefix("iCloud~") else { return nil }

        // What an app's container shows in the Files app is its `Documents`
        // folder, under the app's name; the folder itself is not a crumb.
        if below.first == "Documents" { below.removeFirst() }
        return [iCloudDrive, appName(ofContainer: container)] + below
    }

    /// "iCloud~md~obsidian" is Obsidian: the last word of a container's
    /// reversed-domain identifier, with a capital.
    private static func appName(ofContainer container: String) -> String {
        guard let word = container.split(separator: "~").last, let first = word.first else {
            return container
        }
        return first.uppercased() + word.dropFirst()
    }
}
