import Foundation
import Testing

@testable import AujourCore

private let english = Locale(identifier: "en_US_POSIX")

// The Journal the tests journal into, and the two seams that would otherwise
// be the device: the wall clock, and the waiting between a keystroke and a
// save. Every test drives all three by hand, so "the user typed for a while
// and then stopped" is a sequence rather than a sleep.
@MainActor
private final class EditorSession {
    let store: TallyingJournalStore

    /// The wall clock the editor reads. Moved by a test to turn the day.
    var now: Date

    /// How long the editor asked to wait, in the order it asked.
    private(set) var pauses: [Duration] = []

    /// What the user types while the editor is waiting — one line per wait.
    /// This is how a test keeps someone typing through a debounce without a
    /// single real second passing.
    var typingWhileWaiting: [String] = []

    /// What the user types while the folder is answering a read — one line
    /// per read. The other half of the same trick: a read is a wait too, and
    /// it is the wait a keystroke has to survive when the file is being
    /// re-read underneath the editor.
    var typingWhileReading: [String] = []

    /// Set to leave the editor's waits open, so that what has been typed stays
    /// in the editor and out of the folder for as long as the test needs.
    ///
    /// The state a debounce is in between a keystroke and the save it will
    /// become — and a state a test cannot otherwise stand still in, because
    /// these waits are instant.
    var holdsTheSaveOpen = false

    private(set) var editor: EntryEditor!

    /// The Content Template days are spawned from, as something a test can
    /// edit mid-session — the file is the App layer's to find (ADR 0005), and
    /// what reaches here is the markdown it found.
    let template = ATemplateSomebodyEdits()

    /// - Parameter template: the markdown a new day is spawned from. `nil` for
    ///   a journal with no template, whose days start blank.
    init(
        files: [String: String] = [:],
        spawningFrom template: String? = nil,
        settings: JournalSettings = .default,
        dayData: DayData = DayData(),
        day: JournalDay? = nil,
        now: Date = instant(2026, 3, 1, 9, 30, in: paris),
        autosave timing: AutosaveTiming = .default
    ) {
        self.template.text = template
        self.store = TallyingJournalStore(files)
        self.now = now
        self.editor = EntryEditor(
            store: store,
            settings: settings,
            spawningFrom: self.template,
            dayData: dayData,
            timeZone: paris,
            locale: english,
            day: day,
            autosave: timing,
            // Strongly, deliberately: the session and its editor are made
            // together and die together at the end of a test, and an unowned
            // clock is one a still-running save can outlive.
            now: { self.now },
            wait: { duration in try await self.wait(duration) }
        )
        // Set after the editor exists, because that is what it types into.
        // The folder reads off the main actor, so this comes back to it.
        store.whileReading = { [self] in
            await MainActor.run {
                guard !typingWhileReading.isEmpty else { return }
                editor.content = typingWhileReading.removeFirst()
            }
        }
    }

    /// Opens the editor and lets any save it starts run to the end.
    func open() async {
        await editor.open()
    }

    /// Types, then lets the autosave that follows run to the end — the test's
    /// stand-in for the seconds the app would spend waiting.
    func type(_ text: String) async {
        editor.content = text
        await editor.autosave?.value
    }

    private func wait(_ duration: Duration) async throws {
        // The real `Task.sleep` gives up when the task is cancelled, and
        // `save()` leans on that to take the write over from the loop.
        try Task.checkCancellation()
        pauses.append(duration)
        if !typingWhileWaiting.isEmpty {
            editor.content = typingWhileWaiting.removeFirst()
        }
        while holdsTheSaveOpen {
            // Until the test says otherwise, or until it is cancelled — which
            // is what `save()` does, and the one way words held here ever
            // reach the folder.
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

/// The Content Template as a test holds it: markdown it can change between
/// two spawns, the way somebody editing the file in another app does.
///
/// Unchecked because the one piece of state is read from whatever executor the
/// editor's read lands on and written from the test, both under the lock.
final class ATemplateSomebodyEdits: ContentTemplateSource, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    /// What the file says right now — set by a test to edit it mid-session.
    var text: String? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func markdown() async -> String? { text }
}

/// A Journal Store that keeps the tally of what was written to it, so a test
/// can say "these keystrokes reached the folder once" rather than only "the
/// folder ended up right".
///
/// Unchecked because the tally is written from the editor's saves and read by
/// the test, one strictly after the other — there is no moment in these tests
/// where both are running.
private final class TallyingJournalStore: JournalStore, @unchecked Sendable {
    private let folder: InMemoryJournalStore

    /// Every write, in order.
    private(set) var writes: [(path: String, text: String)] = []

    /// Set to make the folder refuse the next write, as a disk that filled up
    /// or an iCloud file that has not come down would.
    var refuseWrites: (any Error)?

    /// Set to make the folder refuse to be read, as a file iCloud has not
    /// brought down would.
    var refuseReads: (any Error)?

    /// What happens while the folder is answering a read — the test's way of
    /// putting a keystroke in the middle of one.
    var whileReading: (@Sendable () async -> Void)?

    /// A path something else gets to first: the folder is shared, so a name
    /// picked from a listing can be taken by the time the write happens.
    var beatenToTheName: String?

    init(_ files: [String: String] = [:]) {
        folder = InMemoryJournalStore(files)
    }

    func listFiles() async throws -> [String] { try await folder.listFiles() }

    func fileExists(at relativePath: String) async throws -> Bool {
        if let refuseReads { throw refuseReads }
        return try await folder.fileExists(at: relativePath)
    }

    func read(at relativePath: String) async throws -> Data {
        if let refuseReads { throw refuseReads }
        await whileReading?()
        return try await folder.read(at: relativePath)
    }

    func write(_ contents: Data, at relativePath: String) async throws {
        if let refuseWrites { throw refuseWrites }
        writes.append((relativePath, String(decoding: contents, as: UTF8.self)))
        try await folder.write(contents, at: relativePath)
    }

    func create(_ contents: Data, at relativePath: String) async throws {
        if let refuseWrites { throw refuseWrites }
        if relativePath == beatenToTheName {
            // Once: the caller crosses the name off and picks the next.
            beatenToTheName = nil
            throw JournalStoreError.fileAlreadyExists(relativePath)
        }
        writes.append((relativePath, String(decoding: contents, as: UTF8.self)))
        try await folder.create(contents, at: relativePath)
    }

    func move(from source: String, to destination: String) async throws {
        try await folder.move(from: source, to: destination)
    }

    /// A write nobody in Aujour made: Obsidian saving the same file, or iCloud
    /// bringing another device's version down. Untallied, because the tally is
    /// what Aujour itself wrote.
    func somebodyElseWrites(_ text: String, at path: String) async throws {
        try await folder.writeText(text, at: path)
    }

    /// The same, for a file that stops being at the Entry's path — a daily
    /// note dragged into a folder of its own in Obsidian. The seam has no
    /// delete (nothing in v1 removes a file), so this is a move out of the
    /// way, which is what the Entry's path sees either way.
    func somebodyElseTakesAway(_ path: String) async throws {
        try await folder.move(from: path, to: "Archive/moved-away.md")
    }
}

@Suite("Opening today's Entry")
@MainActor
struct EntryEditorOpeningTests {
    @Test("a day that has been journaled opens on what the file says")
    func anExistingEntryLoads() async throws {
        let session = EditorSession(files: ["2026/03/2026-03-01.md": "Walked to the market.\n"])

        await session.open()

        #expect(session.editor.day == JournalDay(year: 2026, month: 3, day: 1))
        #expect(session.editor.content == "Walked to the market.\n")
        #expect(session.editor.state.isEditing)
    }

    @Test("an unwritten day opens on the Content Template, resolved")
    func anUnwrittenDayIsSpawnedFromTheTemplate() async throws {
        let session = EditorSession(
            spawningFrom: "# {{title}}\n\nWritten at {{time}}.\n\n{{mood}}\n{{sparkle}}\n"
        )

        await session.open()

        // Core placeholders resolved, an interactive one left as the literal
        // text the editor will own, and an unknown one gone without debris.
        #expect(
            session.editor.content == "# 2026-03-01\n\nWritten at 09:30.\n\n{{mood}}\n\n"
        )
    }

    @Test("the template is read again every time a day is spawned")
    func aTemplateEditedInTheVaultIsWhatTheNextDayStartsFrom() async throws {
        let session = EditorSession(spawningFrom: "# {{title}}\n")
        await session.open()
        #expect(session.editor.content == "# 2026-03-01\n")

        // The user edits the template file in Obsidian. Aujour holds no copy
        // of it to go stale — the file is read at the moment a day is spawned
        // (ADR 0005).
        session.template.text = "## {{title}}\n\nWoke at {{time}}.\n"
        session.now = instant(2026, 3, 2, 9, 30, in: paris)
        await session.editor.reopenIfTheDayTurned()

        #expect(session.editor.content == "## 2026-03-02\n\nWoke at 09:30.\n")
    }

    @Test("a template that cannot be read leaves the day blank, and open")
    func anUnreadableTemplateSpawnsABlankDay() async throws {
        // The file is the user's, wherever they keep it: renamed, moved, on a
        // drive they unplugged, or not yet down from iCloud. A day they cannot
        // write in would be a worse answer than the blank page they had before
        // they set a template at all.
        let session = EditorSession(spawningFrom: nil)

        await session.open()

        #expect(session.editor.content == "")
        #expect(session.editor.state.isEditing)
    }

    @Test("a spawned day's data placeholders are read for that day and formatted")
    func aSpawnedDayReadsItsOwnData() async throws {
        var settings = JournalSettings.default
        settings.dataPlaceholders[.events].timeFormat = MomentFormat("h:mm a")
        // A backfill: the 28th of February, opened on the 1st of March. The
        // meetings have to be the 28th's.
        let session = EditorSession(
            spawningFrom: "# {{title}}\n\n## Today\n{{events}}\n",
            settings: settings,
            dayData: DayData([.events: ADayInTheCalendar()]),
            day: JournalDay(year: 2026, month: 2, day: 28)
        )

        await session.open()

        #expect(
            session.editor.content
                == "# 2026-02-28\n\n## Today\n- 9:00 am 2026-02-28\n"
        )
    }

    @Test("a day whose data has nothing in it spawns per the formatting settings")
    func anEmptyDaySpawnsItsEmptyText() async throws {
        var settings = JournalSettings.default
        settings.dataPlaceholders[.events].whenEmpty = "_nothing in the calendar_"
        let session = EditorSession(
            spawningFrom: "## Today\n{{events}}\n",
            settings: settings,
            dayData: DayData([.events: ADayInTheCalendar(holding: [])])
        )

        await session.open()

        #expect(session.editor.content == "## Today\n_nothing in the calendar_\n")
    }

    @Test("spawning an unwritten day touches nothing on disk")
    func spawningLeavesNoFile() async throws {
        let session = EditorSession(spawningFrom: "# {{title}}\n")

        await session.open()

        #expect(try await session.store.listFiles().isEmpty)
        #expect(session.store.writes.isEmpty)
    }

    @Test("the Entry opened is the current Journal Day, not the calendar date")
    func oneAMBeforeTheRolloverStaysOnYesterday() async throws {
        // 1 AM on March 2nd, with the day turning at 4 AM: still March 1st,
        // and so is the file the first edit creates.
        let session = EditorSession(
            settings: JournalSettings(rolloverHour: RolloverHour(hour: 4)!),
            now: instant(2026, 3, 2, 1, 0, in: paris)
        )

        await session.open()
        await session.type("Home late.")

        #expect(session.editor.day == JournalDay(year: 2026, month: 3, day: 1))
        #expect(try await session.store.listFiles() == ["2026/03/2026-03-01.md"])
    }

    @Test("the Content Template's dates follow the Entry's own file name")
    func bareDatePlaceholderTracksThePathTemplate() async throws {
        let session = EditorSession(
            spawningFrom: "{{date}}",
            settings: JournalSettings(pathTemplate: "[Journal]/YYYY/MM/DD-MM-YYYY")
        )

        await session.open()

        #expect(session.editor.content == "01-03-2026")
    }

    @Test("a Path Template that cannot name a day is reported, not guessed at")
    func anUnusablePathTemplateIsReported() async throws {
        let session = EditorSession(settings: JournalSettings(pathTemplate: "YYYY/MM"))

        await session.open()

        guard case .unavailable(let problem) = session.editor.state else {
            Issue.record("expected the editor to refuse an Entry path it cannot render")
            return
        }
        #expect(problem is PathTemplateError)
    }

    @Test("a folder that cannot be read is reported rather than shown empty")
    func anUnreadableFolderIsReported() async throws {
        let session = EditorSession(files: ["2026/03/2026-03-01.md": ""])
        // Bytes that are not text: a JPEG dropped in the folder under an .md
        // name. Showing it as an empty page would read as a lost day.
        try await session.store.write(Data([0xFF, 0xD8, 0xFF]), at: "2026/03/2026-03-01.md")

        await session.open()

        guard case .unavailable(let problem) = session.editor.state else {
            Issue.record("expected the editor to refuse a file it could not read as text")
            return
        }
        #expect(problem as? JournalStoreError == .contentIsNotText("2026/03/2026-03-01.md"))
    }
}

@Suite("Autosave")
@MainActor
struct EntryEditorAutosaveTests {
    @Test("the first edit is what creates the file, at the template's path")
    func theFirstEditSpawnsTheFile() async throws {
        let session = EditorSession(spawningFrom: "# {{title}}\n")

        await session.open()
        await session.type("# 2026-03-01\n\nWalked to the market.\n")

        #expect(try await session.store.listFiles() == ["2026/03/2026-03-01.md"])
        #expect(
            try await session.store.readText(at: "2026/03/2026-03-01.md")
                == "# 2026-03-01\n\nWalked to the market.\n"
        )
    }

    @Test("the save waits for the typing to stop, and then lands once")
    func typingIsCoalescedIntoOneSave() async throws {
        let session = EditorSession()
        await session.open()

        // Someone typing a sentence: every wait the editor starts is
        // interrupted by the next word.
        session.typingWhileWaiting = ["Walked ", "Walked to ", "Walked to the market."]
        await session.type("Walked")

        #expect(session.pauses == [.seconds(1), .seconds(1), .seconds(1), .seconds(1)])
        #expect(session.store.writes.count == 1)
        #expect(session.store.writes.first?.text == "Walked to the market.")
    }

    @Test("typing that never pauses is still saved, at the ceiling")
    func aLongStretchOfTypingIsSavedAtTheCeiling() async throws {
        let session = EditorSession(
            autosave: AutosaveTiming(afterTyping: .seconds(2), atMost: .seconds(5))
        )
        await session.open()

        session.typingWhileWaiting = ["aa", "aaa", "aaaa"]
        await session.type("a")

        // Two full quiet periods and then the remainder of the ceiling: the
        // words reach the folder while the typing is still going.
        #expect(session.pauses == [.seconds(2), .seconds(2), .seconds(1)])
        #expect(session.store.writes.count == 1)
        #expect(session.store.writes.first?.text == "aaaa")
    }

    @Test("an edit that puts the text back where it started leaves no file")
    func returningToTheSpawnedTextWritesNothing() async throws {
        let session = EditorSession(spawningFrom: "# {{title}}\n")
        await session.open()
        let spawned = session.editor.content

        session.typingWhileWaiting = [spawned]
        await session.type("# 2026-03-01\nOh, never mind.\n")

        #expect(session.store.writes.isEmpty)
        #expect(try await session.store.listFiles().isEmpty)
    }

    @Test("going into the background saves at once, without waiting")
    func backgroundingSavesImmediately() async throws {
        let session = EditorSession()
        await session.open()

        session.editor.content = "Half a thought"
        await session.editor.save()

        #expect(session.store.writes.count == 1)
        #expect(
            try await session.store.readText(at: "2026/03/2026-03-01.md") == "Half a thought"
        )
        // And the wait it had started is over, rather than saving again later.
        #expect(session.editor.autosave == nil)
    }

    @Test("saving with nothing to save writes nothing")
    func aRedundantSaveIsANoOp() async throws {
        let session = EditorSession(files: ["2026/03/2026-03-01.md": "Yesterday's words"])
        await session.open()

        await session.editor.save()

        #expect(session.store.writes.isEmpty)
    }

    @Test("two saves at once write the day once, not over each other")
    func concurrentSavesDoNotRaceEachOther() async throws {
        let session = EditorSession()
        await session.open()
        session.editor.content = "Half a thought"

        // What backgrounding does: SwiftUI reports inactive and then
        // background, and both of them mean save.
        async let first: Void = session.editor.save()
        async let second: Void = session.editor.save()
        _ = await (first, second)

        #expect(session.store.writes.count == 1)
    }

    @Test("a save that fails is reported, and the words stay on screen")
    func aFailedSaveIsReportedAndKeepsTheWords() async throws {
        let session = EditorSession()
        await session.open()

        session.store.refuseWrites = JournalStoreError.pathIsAFolder("2026/03/2026-03-01.md")
        await session.type("Words that could not land")

        #expect(session.editor.content == "Words that could not land")
        #expect(session.editor.saveProblem != nil)
        #expect(try await session.store.listFiles().isEmpty)

        // And the next edit tries again, rather than leaving the day stranded.
        session.store.refuseWrites = nil
        await session.type("Words that could not land, then did")

        #expect(session.editor.saveProblem == nil)
        #expect(
            try await session.store.readText(at: "2026/03/2026-03-01.md")
                == "Words that could not land, then did"
        )
    }
}

@Suite("The Journal Day turning under the editor")
@MainActor
struct EntryEditorDayTurningTests {
    @Test("coming back after the day has turned opens the new day")
    func theEditorMovesToTheNewDay() async throws {
        let session = EditorSession(now: instant(2026, 3, 1, 23, 55, in: paris))
        await session.open()
        session.editor.content = "The last of March 1st."

        session.now = instant(2026, 3, 2, 8, 0, in: paris)
        await session.editor.reopenIfTheDayTurned()

        #expect(session.editor.day == JournalDay(year: 2026, month: 3, day: 2))
        #expect(session.editor.content.isEmpty)
        // Yesterday's words went to yesterday's file on the way out.
        #expect(
            try await session.store.readText(at: "2026/03/2026-03-01.md")
                == "The last of March 1st."
        )
    }

    @Test("words that could not be saved are not left behind by the new day")
    func aDayThatCouldNotBeSavedIsNotAbandoned() async throws {
        let session = EditorSession(now: instant(2026, 3, 1, 23, 55, in: paris))
        await session.open()
        session.store.refuseWrites = JournalStoreError.pathIsAFolder("2026/03/2026-03-01.md")
        await session.type("The last of March 1st.")

        session.now = instant(2026, 3, 2, 8, 0, in: paris)
        await session.editor.reopenIfTheDayTurned()

        // Moving on would put March 1st's words nowhere: the day stays up,
        // with what went wrong, until they land.
        #expect(session.editor.day == JournalDay(year: 2026, month: 3, day: 1))
        #expect(session.editor.content == "The last of March 1st.")
        #expect(session.editor.saveProblem != nil)
    }

    @Test("coming back on the same day leaves what is on screen alone")
    func theEditorKeepsUnsavedWordsOnTheSameDay() async throws {
        let session = EditorSession()
        await session.open()
        session.editor.content = "Mid-sentence"

        session.now = instant(2026, 3, 1, 18, 0, in: paris)
        await session.editor.reopenIfTheDayTurned()

        #expect(session.editor.day == JournalDay(year: 2026, month: 3, day: 1))
        #expect(session.editor.content == "Mid-sentence")
    }
}

@Suite("The Entry's file changing outside Aujour")
@MainActor
struct EntryEditorExternalChangeTests {
    @Test("an edit made elsewhere reaches the screen, and nothing is written back")
    func aCleanEditorTakesTheFilesVersion() async throws {
        let session = EditorSession(files: ["2026/03/2026-03-01.md": "Walked to the market.\n"])
        await session.open()

        try await session.store.somebodyElseWrites(
            "Walked to the market, and back the long way.\n",
            at: "2026/03/2026-03-01.md"
        )
        await session.editor.reloadIfClean()

        #expect(session.editor.content == "Walked to the market, and back the long way.\n")
        // A refresh is a read: the day is not written back over itself, and
        // the words that just arrived are not now waiting to be saved.
        #expect(session.store.writes.isEmpty)
        await session.editor.save()
        #expect(session.store.writes.isEmpty)
    }

    @Test("words that have not been saved yet are never replaced by the file")
    func anEditorWithUnsavedWordsKeepsThem() async throws {
        let session = EditorSession(files: ["2026/03/2026-03-01.md": "Walked to the market.\n"])
        await session.open()
        // Typed and not yet saved: the debounce is still running, so these
        // words exist nowhere but on screen.
        session.holdsTheSaveOpen = true
        session.editor.content = "Walked to the market, and met"

        try await session.store.somebodyElseWrites(
            "Written on the iPad.\n",
            at: "2026/03/2026-03-01.md"
        )
        await session.editor.reloadIfClean()

        #expect(session.editor.content == "Walked to the market, and met")
        // Still unsaved, and still the newest version of the day anybody has:
        // taking the file's would have lost the sentence being typed, and two
        // versions that have both been written is the Parked File's job.
        #expect(session.store.writes.isEmpty)

        // And the words go where they were always going, once the typing has
        // stopped for long enough.
        session.holdsTheSaveOpen = false
        await session.editor.save()
        #expect(
            try await session.store.readText(at: "2026/03/2026-03-01.md")
                == "Walked to the market, and met"
        )
    }

    @Test("a keystroke that lands while the file is being read is not overwritten")
    func typingDuringTheReadWins() async throws {
        let session = EditorSession(files: ["2026/03/2026-03-01.md": "Walked to the market.\n"])
        await session.open()

        try await session.store.somebodyElseWrites(
            "Written on the iPad.\n",
            at: "2026/03/2026-03-01.md"
        )
        // The user starts a sentence in the moment between the folder being
        // asked and the folder answering.
        session.typingWhileReading = ["Walked to the market, and met"]
        await session.editor.reloadIfClean()

        #expect(session.editor.content == "Walked to the market, and met")
    }

    @Test("a day nobody has written on is left as it was spawned")
    func anUnwrittenDayIsNotSpawnedAgain() async throws {
        let session = EditorSession(spawningFrom: "# {{title}}\n\nWritten at {{time}}.\n")
        await session.open()
        let spawned = session.editor.content

        // Somebody else's file, somewhere else in the folder — and an hour
        // gone by, which a second spawn would put in the text.
        try await session.store.somebodyElseWrites("- a thought\n", at: "Inbox/Ideas.md")
        session.now = instant(2026, 3, 1, 10, 30, in: paris)
        await session.editor.reloadIfClean()

        #expect(session.editor.content == spawned)
        #expect(session.store.writes.isEmpty)
    }

    @Test("a day whose file went away is left on screen, not emptied")
    func anEntryWhoseFileVanishedStaysOnScreen() async throws {
        let session = EditorSession(
            files: ["2026/03/2026-03-01.md": "Walked to the market.\n"],
            spawningFrom: "# {{title}}\n"
        )
        await session.open()

        try await session.store.somebodyElseTakesAway("2026/03/2026-03-01.md")
        await session.editor.reloadIfClean()

        // A day taken off the screen because its file was missing for a
        // moment is the app losing the day — and a file is missing for a
        // moment every time something replaces it by deleting first. The
        // words stay, and the next keystroke puts them back on disk.
        #expect(session.editor.content == "Walked to the market.\n")
        #expect(session.store.writes.isEmpty)

        await session.type("Walked to the market, and the file came back.")
        #expect(
            try await session.store.readText(at: "2026/03/2026-03-01.md")
                == "Walked to the market, and the file came back."
        )
    }

    @Test("an Entry that could not be opened is opened when the folder answers")
    func anUnavailableEntryTriesAgain() async throws {
        let session = EditorSession(files: ["2026/03/2026-03-01.md": "Walked to the market.\n"])
        // What a file iCloud has not brought down yet does to an open.
        session.store.refuseReads = JournalStoreError.fileNotFound("2026/03/2026-03-01.md")
        await session.open()
        #expect(session.editor.state.isEditing == false)

        session.store.refuseReads = nil
        await session.editor.reloadIfClean()

        #expect(session.editor.state.isEditing)
        #expect(session.editor.content == "Walked to the market.\n")
    }

    @Test("a folder that will not answer leaves what is on screen alone")
    func aFailedReloadKeepsTheEntryOnScreen() async throws {
        let session = EditorSession(files: ["2026/03/2026-03-01.md": "Walked to the market.\n"])
        await session.open()

        session.store.refuseReads = JournalStoreError.contentIsNotText("2026/03/2026-03-01.md")
        await session.editor.reloadIfClean()

        // Nobody asked for this read, so its failure is not news: the last
        // thing the file said is still true and still on screen.
        #expect(session.editor.state.isEditing)
        #expect(session.editor.content == "Walked to the market.\n")
        #expect(session.editor.saveProblem == nil)
    }
}

// An Embed's target is written relative to the Entry holding it, so the Entry
// is what can find it. Which spellings are read as an embed at all is
// `EntryMarkdownTests`, and which paths a target might be at is
// `EmbedTargetTests`; this is the two of them over a folder.
@Suite("What an Entry's embeds point at")
@MainActor
struct EntryAttachmentTests {
    private func session(holding attachments: [String: String]) -> EditorSession {
        EditorSession(files: attachments.merging(["2026/03/2026-03-01.md": "![a](b.jpg)\n"]) { a, _ in a })
    }

    @Test("a target beside the entry is found, and so is one up and across")
    func targetsRelativeToTheEntry() async throws {
        let session = session(holding: [
            "2026/03/market.jpg": "beside it",
            "attachments/2026/03/market.jpg": "up and across",
        ])
        await session.open()

        #expect(await session.editor.text(of: "market.jpg") == "beside it")
        #expect(
            await session.editor.text(of: "../../attachments/2026/03/market.jpg")
                == "up and across"
        )
        // Obsidian's bare name, which is a search of the whole folder — and
        // which finds the one beside the Entry first.
        #expect(await session.editor.text(of: "market.jpg") == "beside it")
    }

    @Test("a bare name is found wherever in the folder it is")
    func targetsFoundByName() async throws {
        let session = session(holding: ["attachments/2026/03/market.jpg": "a photograph"])
        await session.open()

        #expect(await session.editor.text(of: "market.jpg") == "a photograph")
    }

    // Every way of failing is the same answer, because they all mean the same
    // thing on screen: the embed is drawn as the markdown it is.
    @Test("a target naming nothing in the folder is nothing at all")
    func targetsThatFindNothing() async throws {
        let session = session(holding: ["2026/03/market.jpg": "a photograph"])
        await session.open()

        #expect(await session.editor.attachment(named: "nothing.jpg") == nil)
        #expect(await session.editor.attachment(named: "https://example.com/a.jpg") == nil)
        #expect(await session.editor.attachment(named: "") == nil)
    }

    // The user pointed Aujour at one folder. An Entry that names its way out
    // of it names somebody else's file, and the file system is never asked.
    @Test("a target that climbs out of the journal root finds nothing")
    func targetsOutsideTheFolder() async throws {
        let session = session(holding: [:])
        await session.open()

        #expect(await session.editor.attachment(named: "../../../../etc/passwd") == nil)
    }
}

// The other direction: a photograph handed to the Entry, which is the only
// object holding both halves of where it goes — the Journal Day the Attachment
// Path Template renders for, and the Entry path the embed is written relative
// to. Which name and which path that comes to is `AttachmentTests`; this is
// that decision over a folder, and what the folder has in it afterwards.
@Suite("Adding a photograph to an Entry")
@MainActor
struct AddingAnAttachmentTests {
    private let photograph = Data("a photograph".utf8)

    @Test("it is written under the Attachment Path Template, and the Entry finds it back")
    func writtenAndFoundAgain() async throws {
        let session = EditorSession()
        await session.open()

        let added = try await session.editor.attach(photograph, keeping: .jpeg)

        #expect(added.path == "attachments/2026/03/2026-03-01.jpg")
        #expect(added.embed == "![](../../attachments/2026/03/2026-03-01.jpg)")
        // The round trip that matters: what was written is what the embed
        // written beside it goes on to find.
        #expect(await session.editor.text(of: added.reference) == "a photograph")
    }

    // The file goes in before the Entry points at it, so that the embed is a
    // picture the moment it is on screen rather than a line of punctuation
    // that becomes one.
    @Test("the file is in the folder before there is anything pointing at it")
    func writtenBeforeTheEmbed() async throws {
        let session = EditorSession()
        await session.open()

        let added = try await session.editor.attach(photograph, keeping: .png)

        #expect(session.store.writes.map(\.path) == [added.path])
        // And the Entry is untouched: putting the embed in is the editor's,
        // through the same door a keystroke goes through.
        #expect(session.editor.content == "")
    }

    @Test("a second photograph of the same day is kept beside the first")
    func aSecondPhotograph() async throws {
        let session = EditorSession()
        await session.open()

        let first = try await session.editor.attach(photograph, keeping: .jpeg)
        let second = try await session.editor.attach(Data("another".utf8), keeping: .jpeg)

        #expect(first.path == "attachments/2026/03/2026-03-01.jpg")
        #expect(second.path == "attachments/2026/03/2026-03-01-2.jpg")
        #expect(await session.editor.text(of: first.reference) == "a photograph")
        #expect(await session.editor.text(of: second.reference) == "another")
    }

    // The folder is shared, so the listing a name was picked from is a moment
    // old — and the refusal is the seam's promise that nothing is written over
    // (ADR 0002), not the write failing.
    @Test("a name taken since the folder was listed is crossed off, not written over")
    func beatenToTheName() async throws {
        let session = EditorSession()
        await session.open()
        session.store.beatenToTheName = "attachments/2026/03/2026-03-01.jpg"

        let added = try await session.editor.attach(photograph, keeping: .jpeg)

        #expect(added.path == "attachments/2026/03/2026-03-01-2.jpg")
        #expect(await session.editor.text(of: added.reference) == "a photograph")
    }

    @Test("the embed-syntax setting decides what is written, not where the file goes")
    func wikiEmbeds() async throws {
        let session = EditorSession(
            settings: JournalSettings(embedSyntax: .obsidianWikiLink)
        )
        await session.open()

        let added = try await session.editor.attach(photograph, keeping: .jpeg)

        #expect(added.path == "attachments/2026/03/2026-03-01.jpg")
        #expect(added.embed == "![[2026-03-01.jpg]]")
        #expect(await session.editor.text(of: added.reference) == "a photograph")
    }

    @Test("an Attachment Path Template that cannot be read writes nothing at all")
    func aTemplateThatCannotBeRead() async throws {
        let session = EditorSession(
            settings: JournalSettings(attachmentPathTemplate: "[photos]/MMMM")
        )
        await session.open()

        await #expect(throws: PathTemplateError.unsupportedToken("MMMM")) {
            try await session.editor.attach(photograph, keeping: .jpeg)
        }
        #expect(session.store.writes.isEmpty)
    }

    // Not reachable from the screen — the row a photograph is added from is up
    // only while a day is being written in — but it is a sentence rather than
    // a silence, because a photograph that inserted nothing is the one outcome
    // a user would repeat.
    @Test("a day that is not open takes no photograph")
    func anEntryThatIsNotOpen() async throws {
        let session = EditorSession()

        await #expect(throws: NoEntryIsOpen()) {
            try await session.editor.attach(photograph, keeping: .jpeg)
        }
        #expect(session.store.writes.isEmpty)
    }
}

extension EntryEditor {
    /// The attachment as the words a test seeded it with — a test's photograph
    /// is a sentence, because the bytes being bytes is not what is in doubt.
    fileprivate func text(of target: String) async -> String? {
        await attachment(named: target).map { String(decoding: $0, as: UTF8.self) }
    }
}

@Suite("Autosave timing")
struct AutosaveTimingTests {
    @Test("each wait is the quiet period, until the ceiling cuts it short")
    func pausesShrinkTowardsTheCeiling() {
        let timing = AutosaveTiming(afterTyping: .seconds(2), atMost: .seconds(5))

        #expect(timing.pause(afterWaiting: .zero) == .seconds(2))
        #expect(timing.pause(afterWaiting: .seconds(2)) == .seconds(2))
        #expect(timing.pause(afterWaiting: .seconds(4)) == .seconds(1))
        #expect(timing.pause(afterWaiting: .seconds(5)) == .zero)
        #expect(timing.pause(afterWaiting: .seconds(9)) == .zero)
    }
}

/// A calendar holding one meeting at nine in the morning of whichever day it
/// is asked about — so the Entry says which day was read.
private struct ADayInTheCalendar: DayItemSource {
    var holding: [String]? = nil

    func items(during day: DateInterval) async -> [DayItem] {
        if let holding {
            return holding.map { DayItem(title: $0) }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = paris
        let nine = calendar.date(byAdding: .hour, value: 9, to: day.start)!
        return [DayItem(title: MomentFormat("YYYY-MM-DD").render(day.start, timeZone: paris), time: nine)]
    }
}

/// A day nobody has written: no Entry in the folder, and nothing typed into
/// the one on screen.
///
/// The one thing about a day the screen cannot read off its words, and the
/// reason it needs telling: a day with no file is spawned from the Content
/// Template exactly as today is, so it arrives headings and all, looking like
/// a day somebody wrote.
@Suite("A day nobody has written")
@MainActor
struct EntryEditorUnwrittenTests {
    @Test("a past day with no file is unwritten")
    func aPastDayWithNoFileIsUnwritten() async throws {
        let session = EditorSession(
            spawningFrom: "# {{title}}\n",
            day: JournalDay(year: 2026, month: 2, day: 26)
        )

        await session.open()

        #expect(session.editor.isUnwritten)
    }

    @Test("a day the folder already holds is not")
    func aDayWithAFileIsNot() async throws {
        let session = EditorSession(
            files: ["2026/02/2026-02-26.md": "Walked to the market.\n"],
            day: JournalDay(year: 2026, month: 2, day: 26)
        )

        await session.open()

        #expect(!session.editor.isUnwritten)
    }

    /// Today too, and that is the point rather than an oversight: what this
    /// says is that there is nothing in the folder, which is as true of this
    /// morning as of a Monday years back. Today's Entry is spawned from the
    /// same template into the same absence of a file.
    @Test("today, before a word of it is typed, is unwritten like any other day")
    func todayIsUnwrittenUntilItIsWritten() async throws {
        let session = EditorSession(spawningFrom: "# {{title}}\n")

        await session.open()

        #expect(session.editor.isUnwritten)
    }

    /// At the first edit and not at the save that follows it. The file appears
    /// at the first edit (`CONTEXT.md`), so that keystroke is when the day
    /// becomes the user's — a page that stayed quiet for the second an
    /// autosave takes would be the app disagreeing with the person typing.
    @Test("the first keystroke ends it, before the folder has heard about it")
    func theFirstEditEndsItBeforeTheSave() async throws {
        let session = EditorSession(
            spawningFrom: "# {{title}}\n",
            day: JournalDay(year: 2026, month: 2, day: 26)
        )
        await session.open()
        // Nothing typed will reach the folder while this is held open, which
        // is the second between a keystroke and the save it becomes.
        session.holdsTheSaveOpen = true

        session.editor.content = "# 2026-02-26\n\nFilled in on Sunday.\n"

        #expect(!session.editor.isUnwritten)
        #expect(session.store.writes.isEmpty)
        session.holdsTheSaveOpen = false
    }

    /// The whole of the claim `CONTEXT.md` makes about a spawned Entry: the
    /// file appears at the first edit. So a day that has been opened and not
    /// typed in has left nothing behind.
    @Test("nothing reaches the folder until the first edit, and then it is written")
    func theFileAppearsAtTheFirstEdit() async throws {
        let session = EditorSession(
            spawningFrom: "# {{title}}\n",
            day: JournalDay(year: 2026, month: 2, day: 26)
        )
        await session.open()

        #expect(session.store.writes.isEmpty)
        #expect(session.editor.isUnwritten)

        await session.type("# 2026-02-26\n\nFilled in on Sunday.\n")

        #expect(session.store.writes.map(\.path) == ["2026/02/2026-02-26.md"])
        #expect(!session.editor.isUnwritten)
    }

    /// The file arriving from somewhere else — Obsidian, or the iPad — while
    /// the day sits open and untyped-in. Somebody wrote it, so it is written.
    @Test("a file arriving under an untouched day ends it")
    func aFileArrivingEndsIt() async throws {
        let session = EditorSession(
            spawningFrom: "# {{title}}\n",
            day: JournalDay(year: 2026, month: 2, day: 26)
        )
        await session.open()
        #expect(session.editor.isUnwritten)

        try await session.store.somebodyElseWrites(
            "Written on the iPad.\n", at: "2026/02/2026-02-26.md"
        )
        await session.editor.reloadIfClean()

        #expect(session.editor.content == "Written on the iPad.\n")
        #expect(!session.editor.isUnwritten)
    }

    /// A day that could not be opened is not a day with nothing in it — it is
    /// a day nothing is known about, and drawing an unreadable folder as an
    /// empty one is the mistake ADR 0001 exists to name.
    @Test("a day the folder would not open is not drawn as an empty one")
    func anUnreadableDayIsNotUnwritten() async throws {
        let session = EditorSession(day: JournalDay(year: 2026, month: 2, day: 26))
        session.store.refuseReads = JournalStoreError.pathIsAFolder("2026/02")

        await session.open()

        #expect(!session.editor.state.isEditing)
        #expect(!session.editor.isUnwritten)
    }
}
