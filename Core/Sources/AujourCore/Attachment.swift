import Foundation

/// A photograph on its way into the Journal Root: where the file goes, what
/// it is called there, and the markdown the Entry points at it with.
///
/// Everything about adding a photograph except the bytes. The picker is the
/// app's, and so is turning what comes back into a format a folder can hold;
/// what is left is three decisions that are arithmetic on paths and names, and
/// so are made here where they are tested against paths rather than against a
/// screenshot of a photograph. ``EmbedTarget`` is the other half of the same
/// arithmetic — this writes the reference that one reads back, and the two are
/// tested against each other.
///
/// ## Nothing is ever written over
///
/// The path is one nothing in the folder holds, and so is the *name*: an
/// embed is looked for by name wherever its path names nothing (``EmbedTarget/
/// match(_:among:)``), in either spelling, so a photograph called the same
/// thing as a note somewhere else in the vault is a photograph the editor
/// might draw the wrong one of. The folder is somebody's vault (ADR 0001), and
/// a name in it that is already theirs is not one to take.
public struct Attachment: Hashable, Sendable {
    /// Where the file is written, relative to the Journal Root.
    public let path: String

    /// What the embed points at: a path relative to the Entry holding it, or —
    /// for the wiki spelling — the file's own name, which is what a wiki embed
    /// means and what Obsidian writes.
    public let reference: String

    /// The markdown itself, in the spelling the Journal Settings ask for.
    public let embed: String

    /// Decides where a photograph added to a day's Entry goes, and how that
    /// Entry points at it.
    ///
    /// - Parameters:
    ///   - format: what the file is kept as, once the app has converted
    ///     whatever the picker handed over (``AttachmentFormat/keeping(_:)``).
    ///   - day: the Journal Day whose Entry it is being added to — which
    ///     names the file, and which the Attachment Path Template is rendered
    ///     for.
    ///   - folders: the Attachment Path Template in force.
    ///   - entryPath: where the Entry holding the embed lives, relative to the
    ///     Journal Root — what the reference is written relative to.
    ///   - syntax: which of the two spellings to write. It decides only that:
    ///     the file goes where the Attachment Path Template says either way.
    ///   - filesInTheFolder: everything the Journal Root holds, so that
    ///     nothing is written over and no name is taken twice. A listing taken
    ///     a moment ago is enough — this decides the *first* free name, and a
    ///     caller whose `create` is refused anyway asks again with that path
    ///     added.
    /// - Throws: `JournalStoreError.invalidPath` for an Entry path no folder
    ///   could hold — the same refusal a Journal Store makes, said here
    ///   because this is where a reference is derived from it.
    public init(
        _ format: AttachmentFormat,
        writtenOn day: JournalDay,
        under folders: AttachmentPathTemplate,
        embeddedIn entryPath: String,
        as syntax: EmbedSyntax,
        beside filesInTheFolder: Set<String>
    ) throws(JournalStoreError) {
        let entry = try RelativePath(entryPath)
        let folder = folders.render(day)
        // By name and not by path, which is the stricter of the two and takes
        // the other with it: a file at the path this would write to is a file
        // whose name is in here.
        let taken = Set(filesInTheFolder.map { ($0 as NSString).lastPathComponent })

        // Terminates because each turn rules out one more name, and a folder
        // holds finitely many.
        var nth = 1
        var name = Self.name(day, nth, format)
        while taken.contains(name) {
            nth += 1
            name = Self.name(day, nth, format)
        }

        // Rendered by a template whose shape was validated when it was built,
        // and a name with no slash in it — so this is a path a folder can
        // hold, said as one rather than re-checked.
        let path = try RelativePath("\(folder)/\(name)")
        self.path = path.string

        switch syntax {
        case .standardMarkdown:
            let relative = Self.reference(to: path, from: entry)
            self.reference = relative
            self.embed = "![](\(relative))"
        case .obsidianWikiLink:
            self.reference = name
            self.embed = "![[\(name)]]"
        }
    }

    // MARK: - What it is called

    /// `2026-03-14.jpg`, and then `2026-03-14-2.jpg`.
    ///
    /// Named after the day rather than after whatever the photo library calls
    /// it, for two reasons. A folder of attachments then sorts and reads the
    /// way the journal does, in Files and in Obsidian both — which is the same
    /// reason the default Attachment Path Template splits them by year and
    /// month. And a wiki embed's target is resolved by name against the whole
    /// vault, so a name that says which day it belongs to is one that could
    /// only be this journal's, where `IMG_0042.jpg` is a name half the world's
    /// folders hold.
    ///
    /// The second photograph of a day is numbered, and not given the Parked
    /// File's `_1`: a `_1` in this folder means a version of somebody's words
    /// that nobody has merged (``ConflictPolicy``), and a second photograph is
    /// not that.
    private static func name(_ day: JournalDay, _ nth: Int, _ format: AttachmentFormat) -> String {
        let stem = nth == 1 ? day.description : "\(day)-\(nth)"
        return "\(stem).\(format.fileExtension)"
    }

    // MARK: - Where it is, said from inside the Entry

    /// The path from the Entry's own folder to the file — `market.jpg` for one
    /// beside it, `../../attachments/2026/03/market.jpg` for one under the
    /// default templates.
    ///
    /// Relative and not from the root, because that is what a markdown link
    /// has always meant and what survives the whole journal being moved: a
    /// vault copied to another machine, or a folder renamed above Aujour's
    /// reach, still has every Entry pointing at every picture.
    private static func reference(to attachment: RelativePath, from entry: RelativePath) -> String {
        var folder = entry.components.dropLast()[...]
        var target = attachment.components[...]
        // Never past the file's own name, which is what is being pointed at.
        while let shared = folder.first, shared == target.first, target.count > 1 {
            folder = folder.dropFirst()
            target = target.dropFirst()
        }

        let climb = Array(repeating: "..", count: folder.count)
        return (climb + target.map(escaped)).joined(separator: "/")
    }

    /// A path component as a markdown link can carry it.
    ///
    /// A link is not read past a space, and a `)` inside one closes it — so a
    /// folder somebody named `My Photos (2026)` is a folder every embed into
    /// it would otherwise point wrongly at. Percent-encoded the way Obsidian
    /// writes it, and read back either way (``EmbedTarget/candidates(for:
    /// inEntryAt:)`` tries the spelling as written and decoded).
    private static func escaped(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .markdownLinkPath) ?? component
    }
}

// MARK: - Putting it in the Entry

extension Attachment {
    /// The edit that writes this embed into an Entry with the cursor here.
    ///
    /// On a line of its own, which is what a picture in a day is: line breaks
    /// are added only where there is not one already, so a caret on the empty
    /// line the return key just made writes no blank lines around it.
    ///
    /// Nothing is taken out. A selection is not replaced the way typing over
    /// one is — the picture goes in after it — because nobody adding a
    /// photograph meant to delete the words they had selected, and no words
    /// are ever silently discarded (`v1-decisions.md`).
    ///
    /// The cursor is left after the picture, where the next sentence goes.
    public func insertion(into source: String, at selection: NSRange) -> MarkdownEdit {
        let text = source as NSString
        // A caret reported past the end of the day is about a version of it
        // that has been replaced since — the end of the Entry is where the
        // picture goes, rather than an exception in front of somebody who is
        // writing.
        let caret = min(max(selection.upperBound, 0), text.length)

        let onALineAlready = caret == 0 || text.character(at: caret - 1) == 0x0A
        let restOfTheLine = caret < text.length && text.character(at: caret) != 0x0A
        let replacement = (onALineAlready ? "" : "\n") + embed + (restOfTheLine ? "\n" : "")

        return MarkdownEdit(
            range: NSRange(location: caret, length: 0),
            replacement: replacement,
            selection: NSRange(
                location: caret + (replacement as NSString).length,
                length: 0
            )
        )
    }
}

// MARK: - What an Attachment is kept as

/// The formats an Attachment is kept in.
///
/// Three, and a rule for everything else. A journal folder outlives the app
/// that wrote it (ADR 0001): it is opened in Obsidian on a Windows laptop,
/// copied to a drive, read years later — so what goes into it has to be
/// something anything can show. JPEG, PNG and GIF are that, and are kept
/// exactly as they arrived.
///
/// Everything else becomes a JPEG, HEIC first among them. HEIC is what an
/// iPhone camera writes and what the picker hands over, and it is also the
/// format that folder on the Windows laptop cannot open. Converting it is the
/// one edit Aujour makes to somebody's photograph, and it is what the promise
/// about the folder is worth.
public enum AttachmentFormat: String, Hashable, Sendable, CaseIterable {
    case jpeg
    case png
    case gif

    /// What the file is called by, in the folder — `jpg` and not `jpeg`,
    /// which is what a camera writes and what a vault is full of.
    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .gif: "gif"
        }
    }

    /// What the system calls this format — the Uniform Type Identifier the app
    /// layer encodes to.
    ///
    /// A string rather than a `UTType`, which is Apple's and which Core may
    /// not import; these identifiers are the stable spelling of the same thing
    /// and are what `keeping(_:)` reads.
    public var contentType: String {
        switch self {
        case .jpeg: "public.jpeg"
        case .png: "public.png"
        case .gif: "com.compuserve.gif"
        }
    }

    /// The format a photograph arriving as this content type is kept in:
    /// itself where the folder can hold it, and JPEG where it cannot.
    ///
    /// The app converts whenever the answer is not what it was handed — which
    /// for a photograph off an iPhone camera is every time.
    public static func keeping(_ contentType: String) -> AttachmentFormat {
        AttachmentFormat.allCases.first { $0.contentType == contentType } ?? .jpeg
    }
}

extension CharacterSet {
    /// What may stand for itself inside a markdown link's `(…)`.
    ///
    /// The URL path set, less the brackets that would close the link early.
    fileprivate static let markdownLinkPath = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "()"))
}
