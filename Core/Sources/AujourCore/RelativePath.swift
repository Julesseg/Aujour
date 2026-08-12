import Foundation

/// A path relative to the Journal Root, in a shape a folder could hold it in.
///
/// Path Templates are validated when they are built, so the paths the domain
/// renders arrive sound. This is for paths assembled any other way — a
/// filename derived from an Entry's, a path read back from settings — where an
/// empty component or a `..` hop would quietly address something outside the
/// folder the user pointed Aujour at.
///
/// A value of this type has been checked. Making one is how a path crosses
/// into a Journal Store, so nothing behind that boundary has to re-ask.
struct RelativePath: Hashable, Sendable, CustomStringConvertible {
    /// The path exactly as it was given, so that a rejection names the
    /// caller's own path back to them.
    let string: String

    /// The folder names the path walks through, ending with the file's own
    /// name. Never empty, and no element is empty.
    let components: [String]

    init(_ string: String) throws(JournalStoreError) {
        guard !string.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw JournalStoreError.invalidPath(string)
        }

        let components = string.split(separator: "/", omittingEmptySubsequences: false)
        for component in components {
            // An empty component is a leading, trailing or doubled slash; `.`
            // and `..` name a folder relative to another one, which a path
            // handed to a file system must never do.
            guard !component.isEmpty, component != ".", component != ".." else {
                throw JournalStoreError.invalidPath(string)
            }
        }

        self.string = string
        self.components = components.map(String.init)
    }

    var description: String { string }
}
