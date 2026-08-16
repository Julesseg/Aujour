import Foundation

/// Where an embed's target lands in the Journal Root.
///
/// `![](market.jpg)` in `2026/03/2026-03-14.md` means the file beside that
/// Entry; `![](../../attachments/2026/03/market.jpg)` — which is what an
/// Attachment written under the default templates looks like from inside a
/// day — means the one two folders up; and `![[market.jpg]]` means the file
/// of that name wherever in the folder it happens to be, because that is what
/// a wiki embed means in Obsidian and the folder may well have been written
/// by Obsidian.
///
/// Three spellings of one question, answered here rather than in the editor
/// so that the answer is unit-tested against paths rather than against a
/// screenshot of a photo. Nothing here touches a file system: this says which
/// paths to ask a Journal Store about, and asking is the store's.
///
/// ## Nothing outside the folder, ever
///
/// A `..` is resolved rather than refused, because a relative embed is how
/// markdown has always pointed at the file next door — but one that climbs
/// past the Journal Root resolves to nothing at all. The user pointed Aujour
/// at one folder, possibly inside their Obsidian vault, and an Entry that
/// names its way out of it is an Entry naming somebody else's file
/// (`VaultSafetyTests`).
public enum EmbedTarget {
    /// The paths worth asking the Journal Store about, in the order to ask —
    /// nearest the Entry first, then from the root — and none of them
    /// escaping the Journal Root.
    ///
    /// Empty when the target names nothing that could be a file in the
    /// folder: a URL, or a climb out of the root. Those embeds are drawn as
    /// their own text, which is what Obsidian shows for them too.
    ///
    /// A leading slash is not one of those. Obsidian writes it to mean "from
    /// the vault root", never the file system's, so it is read that way and
    /// resolved inside the Journal Root like everything else.
    ///
    /// - Parameters:
    ///   - target: what the embed points at, exactly as it is written.
    ///   - entryPath: where the Entry holding it lives, relative to the
    ///     Journal Root — the folder a relative target is relative to.
    public static func candidates(for target: String, inEntryAt entryPath: String?) -> [String] {
        let written = target.trimmingCharacters(in: .whitespaces)
        guard !written.isEmpty, !written.contains("://") else { return [] }

        // A standard-markdown link escapes the spaces in a file name, and a
        // wiki one does not — so both spellings are tried, and a file really
        // called `a%20b.jpg` is still found under the name it has.
        var spellings = [written]
        if let decoded = written.removingPercentEncoding, decoded != written {
            spellings.append(decoded)
        }

        let entryFolder = entryPath.map { ($0 as NSString).deletingLastPathComponent } ?? ""
        var candidates: [String] = []
        for spelling in spellings {
            // A leading slash is Obsidian's way of saying "from the vault
            // root", not the file system's root.
            let fromRoot = spelling.hasPrefix("/") ? String(spelling.dropFirst()) : spelling
            for base in spelling.hasPrefix("/") ? [""] : [entryFolder, ""] {
                guard let path = standardised(base.isEmpty ? fromRoot : base + "/" + fromRoot)
                else { continue }
                if !candidates.contains(path) { candidates.append(path) }
            }
        }
        return candidates
    }

    /// The file name a target is, if it is only a name — Obsidian's
    /// `![[market.jpg]]`, which names a file and leaves finding it to the app
    /// — and `nil` for a target that is a path and has already been looked for
    /// as one.
    ///
    /// Asked before ``match(_:among:)`` and separately from it, because
    /// answering that one costs a listing of the whole Journal Root: a target
    /// that could never be found by name should not pay for the search that
    /// would not have found it.
    public static func bareName(of target: String) -> String? {
        let name = target.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/"), !name.contains("://") else { return nil }
        return name
    }

    /// The file of that name, among everything the Journal Root holds.
    ///
    /// Asked for either spelling of an embed, not only the wiki one: a
    /// `![](market.jpg)` whose file is not where the Entry says is far better
    /// shown as the photograph the user meant than as an apology, and Obsidian
    /// resolves a standard-markdown link by name too.
    ///
    /// The nearest match wins: an exact file name first, then one that
    /// differs only in case, because a vault synced between a Mac and an
    /// iPhone has files whose case nobody chose deliberately.
    public static func match(_ name: String, among files: [String]) -> String? {
        if let exact = files.first(where: { ($0 as NSString).lastPathComponent == name }) {
            return exact
        }
        return files.first {
            ($0 as NSString).lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// The same path with its `.` and `..` hops walked out, or `nil` for one
    /// that walks out of the folder entirely.
    private static func standardised(_ path: String) -> String? {
        var walked: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                guard !walked.isEmpty else { return nil }
                walked.removeLast()
            default:
                walked.append(String(component))
            }
        }
        return walked.isEmpty ? nil : walked.joined(separator: "/")
    }
}
