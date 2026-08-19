import Foundation
import AujourCore

/// The file new Entries are spawned from, and the right to go on reading it
/// after the app is relaunched.
///
/// The user picks it with the system's file picker, so it may be anywhere they
/// keep their writing: beside their entries, in a `Templates` folder elsewhere
/// in their Obsidian vault, in iCloud Drive, on a drive plugged into the iPad.
/// Two ways of reaching it, and which one applies is decided when it is
/// picked (ADR 0005):
///
/// - **Inside the Journal Root.** The path relative to the folder is the whole
///   reference, it is read through the Journal Store like anything else in
///   there, and it travels to the user's other devices in the journal-shaping
///   settings (ADR 0003) — the folder syncs, so the file arrives with it and
///   the iPad needs telling nothing.
/// - **Anywhere else.** A file outside the folder cannot be reached by path at
///   all: what outlives the launch is a *security-scoped bookmark*, bytes that
///   still name the file after it has moved and that carry the permission with
///   the name. A bookmark means nothing on another device, so this one is kept
///   on this device alone — exactly as the Journal Root's own bookmark is —
///   and the other device is pointed at its template once, the same way it is
///   pointed at its folder.
///
/// Read at the moment a day is spawned and never cached: the file is the
/// user's, edited in whatever app they like, and what they changed this
/// morning is what tomorrow starts from.
struct ContentTemplateFile: ContentTemplateSource {
    /// Where the template sits inside the Journal Root, if that is where it
    /// sits — the synced half.
    let insideTheFolder: String

    /// The folder itself, to read it out of. `nil` before a journal is open,
    /// which is a blank page rather than a wait.
    let folder: (any JournalStore)?

    /// The template picked somewhere else on the device, if one was — the
    /// local half.
    let elsewhere: BookmarkedTemplateFile

    func markdown() async -> String? {
        // The bookmark first: picking either kind clears the other, so at most
        // one of these is set, and a bookmark is the more recent answer to
        // "which file?" whenever both somehow are.
        if let text = elsewhere.read() { return text }
        guard !insideTheFolder.isEmpty, let folder else { return nil }
        return try? await folder.readText(at: insideTheFolder)
    }
}

/// A template file outside the Journal Root, remembered between launches.
///
/// The same bargain the chosen journal folder makes (`CustomJournalRoot`): the
/// picker hands over a URL the app may use only while it says it is using it,
/// and a bookmark is the only thing that outlives the launch. The right is
/// taken for the length of one read and given straight back — a template is
/// read for a moment when a day is spawned, not held open the way a folder
/// being journaled into is.
///
/// It reaches the world through the two closures that keep the bookmark, so a
/// test relaunches the app by making a second one over the same storage.
struct BookmarkedTemplateFile: Sendable {
    private let storedBookmark: @Sendable () -> Data?
    private let rememberBookmark: @Sendable (Data?) -> Void

    init(
        storedBookmark: @escaping @Sendable () -> Data?,
        rememberBookmark: @escaping @Sendable (Data?) -> Void
    ) {
        self.storedBookmark = storedBookmark
        self.rememberBookmark = rememberBookmark
    }

    /// Whether a template outside the folder is what this device is spawning
    /// from.
    var isSet: Bool { storedBookmark() != nil }

    /// What to call it on screen: the file's own name, or `nil` when there is
    /// no bookmark or it will not resolve — a name is worth showing only when
    /// it is the name of a file Aujour can actually reach.
    var name: String? {
        resolve()?.file.lastPathComponent
    }

    /// The template's markdown, or `nil` where there is no bookmarked file or
    /// it cannot be read right now.
    ///
    /// Nothing is thrown and nothing is reported. A template that has been
    /// renamed, or is on a drive nobody has plugged in, is a blank page and
    /// not a day that will not open (ADR 0005) — the screen says which file it
    /// is pointed at, which is where that belongs.
    func read() -> String? {
        guard let resolved = resolve() else { return nil }
        let scoped = resolved.file.startAccessingSecurityScopedResource()
        defer { if scoped { resolved.file.stopAccessingSecurityScopedResource() } }

        // A stale bookmark still resolves — it is the warning that it may not
        // next time, once enough has moved — so it is rewritten while there is
        // still something to write it from.
        if resolved.isStale, let refreshed = try? resolved.file.bookmarkData() {
            rememberBookmark(refreshed)
        }
        return try? String(contentsOf: resolved.file, encoding: .utf8)
    }

    /// Remembers a file the user just picked, for every launch after this one.
    ///
    /// The file is only ever read. Nothing is copied out of it and nothing is
    /// written back — it is the user's file, in the user's folder, and
    /// Aujour's whole claim on it is that days start from what it says.
    func remember(_ file: URL) {
        // The picker's URL is one the app may reach only while it says it is
        // reaching it — and making the bookmark counts as reaching it.
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }

        guard let bookmark = try? file.bookmarkData() else { return }
        rememberBookmark(bookmark)
    }

    /// Forgets it — because the user picked another one, or asked for no
    /// template at all. The file itself is untouched.
    func forget() {
        rememberBookmark(nil)
    }

    private func resolve() -> (file: URL, isStale: Bool)? {
        guard let bookmark = storedBookmark() else { return nil }
        var isStale = false
        guard
            let file = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
        else { return nil }
        return (file, isStale)
    }
}

extension BookmarkedTemplateFile {
    static let bookmarkKey = "ContentTemplateBookmark"

    /// The template this device was pointed at, kept in local storage —
    /// per-device by nature, so never through the synced settings seam
    /// (ADR 0003).
    ///
    /// - Parameter key: where the bookmark is kept. Spelled out only by the UI
    ///   suite, which gives each of its journals a key of its own so that one
    ///   test's template is never the next test's.
    static func stored(key: String = BookmarkedTemplateFile.bookmarkKey) -> BookmarkedTemplateFile {
        BookmarkedTemplateFile(
            storedBookmark: { UserDefaults.standard.data(forKey: key) },
            rememberBookmark: { bookmark in
                if let bookmark {
                    UserDefaults.standard.set(bookmark, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        )
    }

    /// A template nobody has picked and nothing remembers — for previews, and
    /// for anything that spawns from the folder or from nothing at all.
    static var unpicked: BookmarkedTemplateFile {
        BookmarkedTemplateFile(storedBookmark: { nil }, rememberBookmark: { _ in })
    }
}
