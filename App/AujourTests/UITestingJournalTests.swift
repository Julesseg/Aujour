import Foundation
import Testing

@testable import Aujour

// The one back door into where the journal lives, held to being shut for
// everybody but the UI suite — and to naming a folder inside the app's own
// Documents when it is open.
@MainActor
@Suite("The UI suite's own journal")
struct UITestingJournalTests {
    @Test("an ordinary launch has no back door at all")
    func nothingInTheEnvironmentMeansNoTestJournal() {
        #expect(UITestingJournal.fromLaunchEnvironment([:]) == nil)
        #expect(UITestingJournal.fromLaunchEnvironment([UITestingJournal.folderKey: ""]) == nil)
    }

    @Test("a folder name that is a path is refused rather than followed")
    func aPathIsNotAFolderName() {
        for name in ["..", ".", "../../elsewhere", "nested/folder", "/"] {
            #expect(
                UITestingJournal.fromLaunchEnvironment([UITestingJournal.folderKey: name]) == nil,
                "'\(name)' should not have been accepted as a folder name"
            )
        }
    }

    @Test("a named folder becomes a journal of its own, spawned from the given template")
    func aNamedFolderBecomesAJournal() async throws {
        let journal = try #require(
            UITestingJournal.fromLaunchEnvironment([
                UITestingJournal.folderKey: "OneTestsJournal",
                UITestingJournal.contentTemplateKey: "# {{title}}\n",
            ])
        )

        await journal.open()

        guard case .open(let root, _) = journal.state else {
            Issue.record("expected a journal in the app's own Documents, got \(journal.state)")
            return
        }
        #expect(root.url.path(percentEncoded: false).contains("Documents/UITests/OneTestsJournal"))
        // The template reached the editor: this is what the spawn test reads.
        let editor = try #require(journal.today)
        #expect(editor.content.hasPrefix("# "))

        try? FileManager.default.removeItem(at: root.url)
    }
}
