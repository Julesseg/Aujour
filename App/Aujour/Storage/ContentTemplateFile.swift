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
///
/// Written only when the user edits it on the Template page, and then back
/// where it lies, through whichever of the two ways it is reached by. That is
/// the one write Aujour makes outside the Journal Root, and it happens because
/// somebody typed into the file they pointed at — never on a spawn, which
/// still only ever reads (ADR 0005).
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

    /// Puts the edited template back in the file it came from.
    ///
    /// Down the same two roads as reading it, and in the same order, so that
    /// the file being written is the one the page was showing: the bookmark
    /// first, then the path inside the folder.
    ///
    /// Throws rather than failing soft, alone among the things done to a
    /// template. A spawn that cannot read the file has somewhere to go — a
    /// blank page, which is a day the user can still write in — and a save
    /// that did not happen has nowhere at all: the words are on screen and
    /// nowhere else, so the screen has to be told (ADR 0001).
    func write(_ markdown: String) async throws {
        if elsewhere.isSet {
            try elsewhere.write(markdown)
            return
        }
        guard !insideTheFolder.isEmpty, let folder else {
            throw TheTemplateCannotBeSaved(name: nil)
        }
        try await folder.writeText(markdown, at: insideTheFolder)
    }
}

/// A template the user edited that could not be put back.
///
/// Said in the two sentences every storage failure here is said in: what
/// happened, and that the words are still on screen. The file is outside the
/// Journal Root or there is no folder open at all, so `JournalRootError` —
/// which is about paths inside a folder — has nothing to say about it.
struct TheTemplateCannotBeSaved: LocalizedError {
    /// The file's own name, where there is one to say.
    let name: String?

    var errorDescription: String? {
        "Aujour couldn't save \(name ?? "your template file")."
    }

    var recoverySuggestion: String? {
        "Your changes are still here. Try again in a moment — the file may have been renamed, moved, or on a drive that isn't plugged in."
    }
}

/// A template file outside the Journal Root, remembered between launches.
///
/// The same bargain the chosen journal folder makes (`CustomJournalRoot`): the
/// picker hands over a URL the app may use only while it says it is using it,
/// and a bookmark is the only thing that outlives the launch. The right is
/// taken for the length of one read — or of one save — and given straight
/// back: a template is reached for a moment when a day is spawned, not held
/// open the way a folder being journaled into is.
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

    /// Puts edited markdown back into the file, where it lies.
    ///
    /// The only write Aujour makes outside the Journal Root, and it happens
    /// for one reason: the user typed into this file on the Template page.
    /// Nothing else touches it — a spawn still only reads (ADR 0005).
    ///
    /// Coordinated for replacing, as every other write this app makes is, so
    /// that Obsidian or the file provider on the other side is told the file
    /// is about to change rather than finding it changed underneath.
    func write(_ markdown: String) throws {
        guard let resolved = resolve() else { throw TheTemplateCannotBeSaved(name: nil) }
        let scoped = resolved.file.startAccessingSecurityScopedResource()
        defer { if scoped { resolved.file.stopAccessingSecurityScopedResource() } }

        // Rewritten while there is something to rewrite it from, exactly as a
        // read does: a stale bookmark still resolves, and this is the warning
        // that next time it may not.
        if resolved.isStale, let refreshed = try? resolved.file.bookmarkData() {
            rememberBookmark(refreshed)
        }

        let contents = Data(markdown.utf8)
        var outcome: (any Error)?
        var refused: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: resolved.file,
            options: .forReplacing,
            error: &refused
        ) { file in
            do {
                // Atomically first, so a save interrupted mid-write leaves the
                // template the user had rather than half of two. It writes its
                // replacement beside the file, which is a folder this app was
                // never given — only the file itself — so where the sandbox
                // refuses, the plain write is what is left, and a template
                // that saves is worth more than one that cannot.
                do {
                    try contents.write(to: file, options: .atomic)
                } catch {
                    try contents.write(to: file)
                }
            } catch {
                outcome = error
            }
        }
        if let refused { throw refused }
        if let outcome { throw outcome }
    }

    /// Remembers a file the user just picked, for every launch after this one.
    ///
    /// Nothing is copied. The file stays where they keep it, and Aujour's
    /// whole claim on it is that days start from what it says — and that the
    /// Template page can edit it in place.
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
