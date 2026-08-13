import Foundation
import Testing
@testable import AujourCore

// The fake is only worth testing against a real folder's behavior, so these
// read as claims about folders: what a listing shows after a write, what a
// move leaves behind, what happens when something is already there.
@Suite("In-memory Journal Store")
struct InMemoryJournalStoreTests {
    @Test("a listing shows the seeded files, and their content round-trips")
    func seededFilesAreListedAndReadable() async throws {
        let store: any JournalStore = InMemoryJournalStore([
            "2026/03/2026-03-01.md": "Walked to the market.\n",
            "Inbox/Ideas.md": "- a thought",
        ])

        #expect(try await store.listFiles() == ["2026/03/2026-03-01.md", "Inbox/Ideas.md"])
        #expect(try await store.readText(at: "2026/03/2026-03-01.md") == "Walked to the market.\n")
        #expect(try await store.readText(at: "Inbox/Ideas.md") == "- a thought")
    }

    @Test("a written file appears in the listing, folders and all")
    func writesShowUpInListings() async throws {
        let store: any JournalStore = InMemoryJournalStore()

        try await store.writeText("Today.", at: "2026/03/2026-03-01.md")

        #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
        #expect(try await store.fileExists(at: "2026/03/2026-03-01.md"))
        #expect(try await store.readText(at: "2026/03/2026-03-01.md") == "Today.")
    }

    @Test("writing again replaces the content, as autosave needs it to")
    func writingOverAnExistingFileReplacesIt() async throws {
        let store: any JournalStore = InMemoryJournalStore(["day.md": "first"])

        try await store.writeText("second", at: "day.md")

        #expect(try await store.readText(at: "day.md") == "second")
        #expect(try await store.listFiles() == ["day.md"])
    }

    @Test("only files are listed — the folders they sit in are not files")
    func foldersAreNotFiles() async throws {
        let store: any JournalStore = InMemoryJournalStore(["2026/03/2026-03-01.md": ""])

        #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
        #expect(try await store.fileExists(at: "2026") == false)
        #expect(try await store.fileExists(at: "2026/03") == false)
    }

    @Test("reading a file that is not there fails, rather than reading empty")
    func readingAMissingFileFails() async throws {
        let store: any JournalStore = InMemoryJournalStore(["day.md": "text"])

        #expect(try await store.fileExists(at: "missing.md") == false)
        await #expect(throws: JournalStoreError.fileNotFound("missing.md")) {
            try await store.read(at: "missing.md")
        }
    }

    @Test("a move takes the content with it and leaves nothing behind")
    func moveRelocatesTheFile() async throws {
        let store: any JournalStore = InMemoryJournalStore([
            "2026-03-01.md": "Walked to the market.\n"
        ])

        try await store.move(from: "2026-03-01.md", to: "2026/03/2026-03-01.md")

        #expect(try await store.listFiles() == ["2026/03/2026-03-01.md"])
        #expect(try await store.readText(at: "2026/03/2026-03-01.md") == "Walked to the market.\n")
        #expect(try await store.fileExists(at: "2026-03-01.md") == false)
    }

    @Test("a move onto an occupied path is refused, and loses neither version")
    func moveNeverOverwrites() async throws {
        let store: any JournalStore = InMemoryJournalStore([
            "2026-03-01.md": "incoming",
            "2026/03/2026-03-01.md": "already there",
        ])

        await #expect(throws: JournalStoreError.fileAlreadyExists("2026/03/2026-03-01.md")) {
            try await store.move(from: "2026-03-01.md", to: "2026/03/2026-03-01.md")
        }

        #expect(try await store.readText(at: "2026-03-01.md") == "incoming")
        #expect(try await store.readText(at: "2026/03/2026-03-01.md") == "already there")
    }

    @Test("moving a file that is not there fails")
    func movingAMissingFileFails() async throws {
        let store: any JournalStore = InMemoryJournalStore()

        await #expect(throws: JournalStoreError.fileNotFound("missing.md")) {
            try await store.move(from: "missing.md", to: "day.md")
        }
    }

    @Test("a move to where the file already is changes nothing")
    func movingAFileOntoItselfIsANoOp() async throws {
        let store: any JournalStore = InMemoryJournalStore(["day.md": "text"])

        try await store.move(from: "day.md", to: "day.md")

        #expect(try await store.readText(at: "day.md") == "text")
    }

    @Test("a file cannot be where a folder is, or a folder where a file is")
    func filesAndFoldersCannotOccupyTheSamePath() async throws {
        let store: any JournalStore = InMemoryJournalStore([
            "2026/03/2026-03-01.md": "",
            "notes.md": "",
        ])

        // "2026/03" is a folder in this store: something is already under it.
        await #expect(throws: JournalStoreError.pathIsAFolder("2026/03")) {
            try await store.writeText("", at: "2026/03")
        }
        // ...while "notes.md" is a file, so nothing can live inside it.
        await #expect(throws: JournalStoreError.pathIsNotAFolder("notes.md")) {
            try await store.writeText("", at: "notes.md/inner.md")
        }
        await #expect(throws: JournalStoreError.pathIsNotAFolder("notes.md")) {
            try await store.move(from: "2026/03/2026-03-01.md", to: "notes.md/inner.md")
        }
    }

    @Test("attachment bytes survive the round trip untouched")
    func binaryContentRoundTrips() async throws {
        let store: any JournalStore = InMemoryJournalStore()
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        try await store.write(jpegBytes, at: "attachments/2026/03/photo.jpg")

        #expect(try await store.read(at: "attachments/2026/03/photo.jpg") == jpegBytes)
    }

    @Test("a file whose bytes are not text fails to read as text, with its path named")
    func nonTextContentFailsToReadAsText() async throws {
        let store: any JournalStore = InMemoryJournalStore()
        try await store.write(Data([0xFF, 0xD8, 0xFF]), at: "photo.jpg")

        await #expect(throws: JournalStoreError.contentIsNotText("photo.jpg")) {
            try await store.readText(at: "photo.jpg")
        }
    }

    @Test("text is stored as UTF-8, accents and emoji included")
    func textIsStoredAsUTF8() async throws {
        let store: any JournalStore = InMemoryJournalStore()

        try await store.writeText("Café ☕️ — déjà vu", at: "day.md")

        #expect(try await store.readText(at: "day.md") == "Café ☕️ — déjà vu")
        #expect(try await store.read(at: "day.md") == Data("Café ☕️ — déjà vu".utf8))
    }
}

@Suite("Journal Store paths")
struct JournalStorePathTests {
    @Test("a checked path keeps what it was given, and knows the folders it walks")
    func aCheckedPathExposesItsComponents() throws {
        let path = try RelativePath("2026/03/2026-03-01.md")

        #expect(path.string == "2026/03/2026-03-01.md")
        #expect(path.components == ["2026", "03", "2026-03-01.md"])
        #expect(path.description == "2026/03/2026-03-01.md")
    }

    @Test("every path a Path Template renders is one a store will take")
    func renderedEntryPathsAreAlwaysAcceptable() throws {
        let templates = [
            PathTemplate.default,
            try PathTemplate("YYYY-MM-DD"),
            try PathTemplate("[Daily Notes]/YYYY/[Q]MM/YYYY-MM-DD"),
        ]

        for template in templates {
            for day in [
                JournalDay(year: 2026, month: 1, day: 1),
                JournalDay(year: 2026, month: 3, day: 1),
                JournalDay(year: 2026, month: 12, day: 31),
            ] {
                #expect(throws: Never.self) { try RelativePath(template.render(day)) }
            }
        }
        let attachmentFolder = AttachmentPathTemplate.default
            .render(JournalDay(year: 2026, month: 3, day: 1))
        #expect(throws: Never.self) { try RelativePath(attachmentFolder) }
    }

    @Test("a folder lasts exactly as long as a file is under it")
    func aFolderVanishesWhenItsLastFileMovesOut() async throws {
        let store: any JournalStore = InMemoryJournalStore(["2026/03/2026-03-01.md": "text"])

        try await store.move(from: "2026/03/2026-03-01.md", to: "2026-03-01.md")

        // The documented divergence from a disk, pinned here so that changing
        // it is a decision rather than an accident: a disk would keep the empty
        // folder and refuse a file at its path. Nothing in the domain writes
        // one there — a Path Template's file and folder components cannot swap.
        try await store.writeText("", at: "2026/03")
        #expect(try await store.listFiles() == ["2026-03-01.md", "2026/03"])
    }

    @Test("paths that no folder could hold are refused, whichever way they arrive")
    func unusablePathsAreRefused() async throws {
        let store: any JournalStore = InMemoryJournalStore(["day.md": "text"])

        for path in ["", "   ", "/2026/day.md", "2026//day.md", "2026/day.md/", "."] {
            await #expect(throws: JournalStoreError.invalidPath(path), "writing \(path)") {
                try await store.writeText("", at: path)
            }
            await #expect(throws: JournalStoreError.invalidPath(path), "reading \(path)") {
                try await store.read(at: path)
            }
            await #expect(throws: JournalStoreError.invalidPath(path), "asking about \(path)") {
                try await store.fileExists(at: path)
            }
            await #expect(throws: JournalStoreError.invalidPath(path), "moving to \(path)") {
                try await store.move(from: "day.md", to: path)
            }
            await #expect(throws: JournalStoreError.invalidPath(path), "moving from \(path)") {
                try await store.move(from: path, to: "elsewhere.md")
            }
        }
    }

    @Test("a path that hops out of the Journal Root is refused")
    func pathsThatEscapeTheJournalRootAreRefused() async throws {
        let store: any JournalStore = InMemoryJournalStore()

        for path in ["../day.md", "2026/../day.md", "2026/./day.md", ".."] {
            await #expect(throws: JournalStoreError.invalidPath(path), "writing \(path)") {
                try await store.writeText("", at: path)
            }
        }
    }

    @Test("every rejection names the path it is about")
    func errorsNameTheirPath() {
        #expect(JournalStoreError.fileNotFound("2026/day.md").description.contains("2026/day.md"))
        #expect(JournalStoreError.invalidPath("../day.md").description.contains("../day.md"))
        #expect(JournalStoreError.fileAlreadyExists("day.md").description.contains("day.md"))
        #expect(JournalStoreError.pathIsAFolder("2026").description.contains("2026"))
        #expect(JournalStoreError.pathIsNotAFolder("day.md").description.contains("day.md"))
        #expect(JournalStoreError.contentIsNotText("photo.jpg").description.contains("photo.jpg"))
    }
}

// The question the calendar asks of a folder. Stores are held as
// `any JournalStore` throughout these tests, the way the App layer holds one,
// so what is exercised is the seam rather than the fake's own signatures.
private func journaledDays(
    in store: any JournalStore,
    matching template: PathTemplate
) async throws -> [JournalDay] {
    try await store.listFiles().compactMap(template.match).sorted()
}

/// The scenario the whole domain is built to answer, driven through the fake:
/// a folder of files, a Path Template and a clock decide which file is today's
/// Entry — and everything else in the folder stays untouched.
@Suite("Journal Store end to end")
struct JournalStoreScenarioTests {
    /// A folder as an Obsidian user would actually have it: entries under the
    /// default template, a Parked File, an attachment, and unrelated notes.
    private func vault() -> any JournalStore {
        InMemoryJournalStore([
            "2026/02/2026-02-28.md": "February's last day.\n",
            "2026/03/2026-03-01.md": "Walked to the market.\n",
            "2026/03/2026-03-01_1.md": "A divergent version, parked.\n",
            "2026/03/Ideas.md": "- not a journal entry",
            "Meetings/Standup.md": "- also not one",
            "attachments/2026/03/photo.jpg": "",
        ])
    }

    @Test("a template and a clock pick today's Entry out of a folder of other files")
    func todaysEntryIsIdentifiedAmongTheVaultsOtherFiles() async throws {
        let store = vault()
        let template = PathTemplate.default

        // 1 AM on March 2nd with a 4 AM rollover: the day being written about
        // is still March 1st.
        let today = JournalDay.current(
            at: instant(2026, 3, 2, 1, in: paris),
            in: paris,
            rolloverHour: RolloverHour(hour: 4)!
        )
        let journaled = try await journaledDays(in: store, matching: template)

        #expect(today == JournalDay(year: 2026, month: 3, day: 1))
        #expect(
            journaled == [
                JournalDay(year: 2026, month: 2, day: 28),
                JournalDay(year: 2026, month: 3, day: 1),
            ]
        )
        #expect(journaled.contains(today))
        #expect(try await store.readText(at: template.render(today)) == "Walked to the market.\n")
    }

    @Test("a day with no file yet is not journaled until something is written")
    func aDayIsJournaledExactlyWhenItsFileExists() async throws {
        let store = vault()
        let template = PathTemplate.default
        let today = JournalDay.current(
            at: instant(2026, 3, 3, 9, in: paris),
            in: paris,
            rolloverHour: .midnight
        )

        #expect(try await store.fileExists(at: template.render(today)) == false)

        // Spawning the Entry is a write at the path the template names, which
        // is all it takes for the day to read back as journaled.
        try await store.writeText("# 2026-03-03\n\nFirst words.\n", at: template.render(today))

        #expect(try await store.fileExists(at: template.render(today)))
        #expect(try await journaledDays(in: store, matching: template).contains(today))
        #expect(
            try await store.readText(at: template.render(today))
                == "# 2026-03-03\n\nFirst words.\n"
        )
    }

    @Test("after moving every Entry, the new template identifies them and the old one does not")
    func migratingEntriesToANewTemplateReshapesWhatIsAnEntry() async throws {
        let store = vault()
        let oldTemplate = PathTemplate.default
        let newTemplate = try PathTemplate("[Journal]/YYYY-MM-DD")

        let entries = try await store.listFiles().compactMap { path in
            oldTemplate.match(path).map { (path: path, day: $0) }
        }
        for entry in entries {
            try await store.move(from: entry.path, to: newTemplate.render(entry.day))
        }

        let files = try await store.listFiles()
        #expect(
            try await journaledDays(in: store, matching: newTemplate)
                == entries.map(\.day).sorted()
        )
        #expect(try await journaledDays(in: store, matching: oldTemplate).isEmpty)
        #expect(files.contains("Journal/2026-03-01.md"))
        #expect(
            try await store.readText(at: "Journal/2026-03-01.md") == "Walked to the market.\n"
        )
        // The files that were never Entries were never touched.
        #expect(files.contains("2026/03/2026-03-01_1.md"))
        #expect(files.contains("Meetings/Standup.md"))
        #expect(files.contains("attachments/2026/03/photo.jpg"))
    }
}
