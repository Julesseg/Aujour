import Foundation
import Testing

@testable import AujourCore

// Where a photograph goes when somebody adds one to a day, what it is called
// there, and how the Entry points at it. All of it is arithmetic on paths and
// names, which is why it is here rather than in the app: the folder work is a
// `create` at the path this decided, and the picture on screen is the same
// embed anybody could have typed by hand.
@Suite("A photograph added to a day")
struct AttachmentTests {
    private let march14 = JournalDay(year: 2026, month: 3, day: 14)
    private let entry = "2026/03/2026-03-14.md"

    // MARK: - Where the file goes

    @Test("it lands under the Attachment Path Template, rendered for its day")
    func path() throws {
        let photo = try attach(.jpeg)

        #expect(photo.path == "attachments/2026/03/2026-03-14.jpg")
    }

    @Test("a template naming no day at all puts every photograph in one folder")
    func aFolderWithNoDayInIt() throws {
        let photo = try attach(.jpeg, under: "[photos]")

        #expect(photo.path == "photos/2026-03-14.jpg")
    }

    // The name is the day, so a folder of attachments sorts the way the
    // journal does — and so a wiki embed's `![[2026-03-14.jpg]]`, which is
    // resolved by name against the whole vault, names something that could
    // only be this journal's.
    @Test("it is named after the day it was added to")
    func namedAfterItsDay() throws {
        let july4 = JournalDay(year: 2026, month: 7, day: 4)
        let photo = try attach(.png, writtenOn: july4, forEntryAt: "2026/07/2026-07-04.md")

        #expect(photo.path == "attachments/2026/07/2026-07-04.png")
    }

    // The second photograph of a day is the second photograph of a day, and
    // not a version of the first that nobody has merged — so it is numbered
    // rather than given the Parked File's `_1`.
    @Test("the next photograph of the same day is numbered rather than written over")
    func aSecondPhotograph() throws {
        let second = try attach(.jpeg, beside: ["attachments/2026/03/2026-03-14.jpg"])
        #expect(second.path == "attachments/2026/03/2026-03-14-2.jpg")

        let third = try attach(
            .jpeg,
            beside: [
                "attachments/2026/03/2026-03-14.jpg",
                "attachments/2026/03/2026-03-14-2.jpg",
            ]
        )
        #expect(third.path == "attachments/2026/03/2026-03-14-3.jpg")
    }

    // Either spelling of an embed is looked for by name when the path it
    // names is not there (`EmbedTarget.match`), so a photograph sharing a name
    // with a note somewhere else in the vault is a photograph the editor might
    // draw the wrong one of.
    @Test("a name already used anywhere in the folder is not taken again")
    func aNameUsedElsewhereInTheVault() throws {
        let photo = try attach(.jpeg, beside: ["Attachments from Obsidian/2026-03-14.jpg"])

        #expect(photo.path == "attachments/2026/03/2026-03-14-2.jpg")
    }

    // A name is a whole name, extension included: `2026-03-14.png` beside
    // `2026-03-14.jpg` is two files nothing could confuse, and neither an
    // embed nor the Files app has to be told which is which.
    @Test("a photograph in another format is not numbered around one it cannot clash with")
    func anotherFormatOfTheSameDay() throws {
        let photo = try attach(.png, beside: ["attachments/2026/03/2026-03-14.jpg"])

        #expect(photo.path == "attachments/2026/03/2026-03-14.png")
    }

    // MARK: - How the Entry points at it

    @Test("the embed points at it relative to the Entry holding it")
    func referencedFromTheEntry() throws {
        let photo = try attach(.jpeg)

        #expect(photo.reference == "../../attachments/2026/03/2026-03-14.jpg")
        #expect(photo.embed == "![](../../attachments/2026/03/2026-03-14.jpg)")
    }

    @Test("a photograph beside the Entry is named and nothing more")
    func referencedFromTheSameFolder() throws {
        let photo = try attach(
            .jpeg, under: "[attachments]", forEntryAt: "attachments/2026-03-14.md"
        )

        #expect(photo.path == "attachments/2026-03-14.jpg")
        #expect(photo.reference == "2026-03-14.jpg")
    }

    @Test("only the folders the two do not share are climbed")
    func theFoldersTheyShare() throws {
        let photo = try attach(.jpeg, under: "YYYY/[photos]")

        #expect(photo.path == "2026/photos/2026-03-14.jpg")
        #expect(photo.reference == "../photos/2026-03-14.jpg")
    }

    // A markdown link is not read past a space, and a `)` inside one closes
    // it — so a folder somebody named "My Photos (2026)" is a folder every
    // embed into it would otherwise point wrongly at.
    @Test("a folder name with spaces or brackets in it is escaped")
    func escapedInTheLink() throws {
        let photo = try attach(.jpeg, under: "[My Photos (all)]")

        #expect(photo.path == "My Photos (all)/2026-03-14.jpg")
        #expect(photo.reference == "../../My%20Photos%20%28all%29/2026-03-14.jpg")
    }

    @Test("the wiki spelling names the file and leaves finding it to the app")
    func wikiEmbeds() throws {
        let photo = try attach(.jpeg, as: .obsidianWikiLink)

        // Still written where the Attachment Path Template says: the setting
        // decides how an Entry points at a file, not where the file goes.
        #expect(photo.path == "attachments/2026/03/2026-03-14.jpg")
        #expect(photo.reference == "2026-03-14.jpg")
        #expect(photo.embed == "![[2026-03-14.jpg]]")
    }

    // The claim the two spellings are worth nothing without: whichever one is
    // written, the folder is asked for the file that was actually created.
    @Test("what is written points back at the file that was written", arguments: [
        EmbedSyntax.standardMarkdown, .obsidianWikiLink,
    ])
    func theEmbedResolvesBackToTheFile(syntax: EmbedSyntax) throws {
        for folders in ["[attachments]/YYYY/MM", "[My Photos (all)]", "YYYY/[photos]"] {
            let photo = try attach(.jpeg, under: folders, as: syntax)

            let looking = EmbedTarget.candidates(for: photo.reference, inEntryAt: entry)
            let byName = EmbedTarget.bareName(of: photo.reference)
                .flatMap { EmbedTarget.match($0, among: [photo.path]) }

            #expect(
                looking.contains(photo.path) || byName == photo.path,
                "\(syntax) under \(folders) wrote \(photo.reference), which does not find \(photo.path)"
            )
        }
    }

    // MARK: - What it is kept as

    // The one edit Aujour makes to somebody's photograph, and the reason for
    // it: HEIC is what the camera writes and what a vault opened anywhere else
    // may not show at all.
    @Test("a HEIC photograph is kept as a JPEG")
    func heicBecomesJpeg() {
        #expect(AttachmentFormat.keeping("public.heic") == .jpeg)
        #expect(AttachmentFormat.keeping("public.heif") == .jpeg)
        #expect(AttachmentFormat.keeping("public.heics") == .jpeg)
    }

    @Test("the formats a vault can hold are kept as they arrived")
    func portableFormatsAreKept() {
        #expect(AttachmentFormat.keeping("public.jpeg") == .jpeg)
        #expect(AttachmentFormat.keeping("public.png") == .png)
        #expect(AttachmentFormat.keeping("com.compuserve.gif") == .gif)
    }

    // Anything else — a RAW file, a TIFF, a format nobody has heard of — is a
    // photograph a vault may not be able to show either, so it goes the same
    // way HEIC does rather than into the folder as itself.
    @Test("anything else becomes a JPEG too")
    func everythingElseBecomesJpeg() {
        #expect(AttachmentFormat.keeping("com.adobe.raw-image") == .jpeg)
        #expect(AttachmentFormat.keeping("public.tiff") == .jpeg)
        #expect(AttachmentFormat.keeping("") == .jpeg)
    }

    @Test("each format carries the extension a vault knows it by")
    func extensions() {
        #expect(AttachmentFormat.jpeg.fileExtension == "jpg")
        #expect(AttachmentFormat.png.fileExtension == "png")
        #expect(AttachmentFormat.gif.fileExtension == "gif")
    }

    // MARK: - Where the embed goes in the Entry

    @Test("it goes in at the caret, on a line of its own")
    func insertedAtTheCaret() throws {
        let photo = try attach(.jpeg, as: .obsidianWikiLink)
        let day = "Walked to the market.\nAnd back the long way."

        let edit = photo.insertion(into: day, at: NSRange(location: 21, length: 0))

        #expect(edit.range == NSRange(location: 21, length: 0))
        #expect(edit.replacement == "\n![[2026-03-14.jpg]]")
        // After the picture, which is where the next sentence goes.
        #expect(edit.selection == NSRange(location: 41, length: 0))
    }

    @Test("a caret already on an empty line writes no line breaks at all")
    func insertedOnAnEmptyLine() throws {
        let photo = try attach(.jpeg, as: .obsidianWikiLink)

        let edit = photo.insertion(into: "Milk\n", at: NSRange(location: 5, length: 0))

        #expect(edit.replacement == "![[2026-03-14.jpg]]")
        #expect(edit.selection == NSRange(location: 24, length: 0))
    }

    @Test("a caret in the middle of a line leaves the rest of it below")
    func insertedMidLine() throws {
        let photo = try attach(.jpeg, as: .obsidianWikiLink)

        let edit = photo.insertion(into: "Milk and bread", at: NSRange(location: 4, length: 0))

        #expect(edit.replacement == "\n![[2026-03-14.jpg]]\n")
        // On the line the rest of the sentence was pushed onto.
        #expect(edit.selection == NSRange(location: 25, length: 0))
    }

    @Test("an empty day takes the embed and nothing else")
    func insertedIntoAnEmptyDay() throws {
        let photo = try attach(.jpeg, as: .obsidianWikiLink)

        let edit = photo.insertion(into: "", at: NSRange(location: 0, length: 0))

        #expect(edit.range == NSRange(location: 0, length: 0))
        #expect(edit.replacement == "![[2026-03-14.jpg]]")
    }

    // Nobody adding a photograph meant to delete the words they had selected,
    // and no words are ever silently discarded — so it goes in after them.
    @Test("words that were selected are kept, and the picture goes after them")
    func insertedAfterASelection() throws {
        let photo = try attach(.jpeg, as: .obsidianWikiLink)

        let edit = photo.insertion(into: "Milk and bread", at: NSRange(location: 0, length: 4))

        #expect(edit.range == NSRange(location: 4, length: 0))
        #expect(edit.replacement == "\n![[2026-03-14.jpg]]\n")
    }

    // A caret reported past the end of the day is a caret about a version of
    // it that has been replaced since — an exception in front of somebody who
    // is writing, rather than a misplaced picture.
    @Test("a caret past the end of the day writes at the end of it")
    func insertedPastTheEnd() throws {
        let photo = try attach(.jpeg, as: .obsidianWikiLink)

        let edit = photo.insertion(into: "Milk", at: NSRange(location: 99, length: 0))

        #expect(edit.range == NSRange(location: 4, length: 0))
        #expect(edit.replacement == "\n![[2026-03-14.jpg]]")
    }

    // MARK: - Paths no folder could hold

    @Test("an Entry path a folder could not hold is refused rather than resolved")
    func aRefusedEntryPath() {
        #expect(throws: JournalStoreError.invalidPath("../elsewhere/2026-03-14.md")) {
            try attach(.jpeg, forEntryAt: "../elsewhere/2026-03-14.md")
        }
    }

    // MARK: - Adding one

    private func attach(
        _ format: AttachmentFormat,
        writtenOn day: JournalDay? = nil,
        under folders: String = "[attachments]/YYYY/MM",
        forEntryAt entryPath: String? = nil,
        as syntax: EmbedSyntax = .standardMarkdown,
        beside filesInTheFolder: Set<String> = []
    ) throws -> AujourCore.Attachment {
        // Qualified: Swift Testing has an `Attachment` of its own, for the
        // artifacts a failing test hands back.
        try AujourCore.Attachment(
            format,
            writtenOn: day ?? march14,
            under: AttachmentPathTemplate(folders),
            embeddedIn: entryPath ?? entry,
            as: syntax,
            beside: filesInTheFolder
        )
    }
}
