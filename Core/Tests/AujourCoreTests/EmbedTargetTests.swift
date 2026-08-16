import Foundation
import Testing

@testable import AujourCore

// Which file an embed means. A journal shared with Obsidian holds every way of
// writing that down — beside the Entry, up and across to an attachments
// folder, from the vault root, or by bare file name — and the editor draws a
// picture for all of them or none.

@Suite("Finding what an embed points at")
struct EmbedTargetTests {
    private let day = "2026/03/2026-03-14.md"

    @Test("a bare name is the file beside the entry, and then the one at the root")
    func besideTheEntryFirst() {
        #expect(
            EmbedTarget.candidates(for: "market.jpg", inEntryAt: day)
                == ["2026/03/market.jpg", "market.jpg"]
        )
    }

    // What an Attachment written under the default templates looks like from
    // inside a day: up out of `YYYY/MM`, and across into `attachments`.
    @Test("a relative embed climbs out of the entry's folder")
    func climbingOut() {
        #expect(
            EmbedTarget.candidates(for: "../../attachments/2026/03/market.jpg", inEntryAt: day)
                == ["attachments/2026/03/market.jpg"]
        )
        #expect(
            EmbedTarget.candidates(for: "./market.jpg", inEntryAt: day)
                == ["2026/03/market.jpg", "market.jpg"]
        )
    }

    // The user pointed Aujour at one folder. An Entry that names its way out
    // of it names somebody else's file, and gets a picture of nothing.
    @Test("a target that climbs past the journal root resolves to nothing")
    func climbingOutOfTheFolder() {
        #expect(EmbedTarget.candidates(for: "../../../../etc/passwd", inEntryAt: day).isEmpty)
        #expect(EmbedTarget.candidates(for: "../secrets.jpg", inEntryAt: "day.md").isEmpty)
        #expect(EmbedTarget.candidates(for: "..", inEntryAt: nil).isEmpty)
    }

    @Test("a leading slash is the journal root, not the file system's")
    func fromTheRoot() {
        #expect(
            EmbedTarget.candidates(for: "/attachments/market.jpg", inEntryAt: day)
                == ["attachments/market.jpg"]
        )
    }

    // A standard-markdown link escapes the spaces in a file name and a wiki
    // one does not, so both spellings are tried — and a file really called
    // `a%20b.jpg` is still found under the name it has.
    @Test("a name with escaped spaces is looked for both ways")
    func percentEscapes() {
        #expect(
            EmbedTarget.candidates(for: "the%20market.jpg", inEntryAt: day) == [
                "2026/03/the%20market.jpg", "the%20market.jpg",
                "2026/03/the market.jpg", "the market.jpg",
            ]
        )
    }

    @Test("what is not a file in the folder is not looked for at all")
    func notFilesAtAll() {
        #expect(EmbedTarget.candidates(for: "https://example.com/a.jpg", inEntryAt: day).isEmpty)
        #expect(EmbedTarget.candidates(for: "   ", inEntryAt: day).isEmpty)
        #expect(EmbedTarget.candidates(for: "", inEntryAt: nil).isEmpty)
    }

    @Test("an entry whose path is not known yet is asked about from the root")
    func noEntryPath() {
        #expect(EmbedTarget.candidates(for: "market.jpg", inEntryAt: nil) == ["market.jpg"])
    }

    @Test("a bare wiki name is matched against the file names in the folder")
    func matchingByName() {
        let files = ["2026/03/2026-03-14.md", "attachments/2026/03/market.jpg", "other.jpg"]
        #expect(EmbedTarget.match("market.jpg", among: files) == "attachments/2026/03/market.jpg")
        #expect(EmbedTarget.match("Market.JPG", among: files) == "attachments/2026/03/market.jpg")
        #expect(EmbedTarget.match("nothing.jpg", among: files) == nil)
        // A path has already been looked for as one.
        #expect(EmbedTarget.match("attachments/2026/03/market.jpg", among: files) == nil)
    }

    // The paths this hands out cross into a Journal Store, which refuses
    // anything a folder could not hold.
    @Test("every candidate is a path a journal store will accept")
    func candidatesAreSoundPaths() throws {
        let targets = [
            "market.jpg", "./a/b.jpg", "../../attachments/x.png", "/at the root.jpg",
            "a%20b.jpg", "deep/deeper/deepest.heic",
        ]
        for target in targets {
            for candidate in EmbedTarget.candidates(for: target, inEntryAt: day) {
                #expect(throws: Never.self) { try RelativePath(candidate) }
            }
        }
    }
}
