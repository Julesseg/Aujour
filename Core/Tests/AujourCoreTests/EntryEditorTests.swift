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

    private(set) var editor: EntryEditor!

    init(
        files: [String: String] = [:],
        settings: JournalSettings = .default,
        now: Date = instant(2026, 3, 1, 9, 30, in: paris),
        autosave timing: AutosaveTiming = .default
    ) {
        self.store = TallyingJournalStore(files)
        self.now = now
        self.editor = EntryEditor(
            store: store,
            settings: settings,
            timeZone: paris,
            locale: english,
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
    }
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
            settings: JournalSettings(
                contentTemplate: "# {{title}}\n\nWritten at {{time}}.\n\n{{mood}}\n{{sparkle}}\n"
            )
        )

        await session.open()

        // Core placeholders resolved, an interactive one left as the literal
        // text the editor will own, and an unknown one gone without debris.
        #expect(
            session.editor.content == "# 2026-03-01\n\nWritten at 09:30.\n\n{{mood}}\n\n"
        )
    }

    @Test("spawning an unwritten day touches nothing on disk")
    func spawningLeavesNoFile() async throws {
        let session = EditorSession(settings: JournalSettings(contentTemplate: "# {{title}}\n"))

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
            settings: JournalSettings(
                pathTemplate: "[Journal]/YYYY/MM/DD-MM-YYYY",
                contentTemplate: "{{date}}"
            )
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
        let session = EditorSession(settings: JournalSettings(contentTemplate: "# {{title}}\n"))

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
        let session = EditorSession(settings: JournalSettings(contentTemplate: "# {{title}}\n"))
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
        session.editor.content = "Walked to the market, and met"

        try await session.store.somebodyElseWrites(
            "Written on the iPad.\n",
            at: "2026/03/2026-03-01.md"
        )
        await session.editor.reloadIfClean()

        #expect(session.editor.content == "Walked to the market, and met")
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
        let session = EditorSession(
            settings: JournalSettings(contentTemplate: "# {{title}}\n\nWritten at {{time}}.\n")
        )
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

    @Test("a day whose file was taken away goes back to being unwritten")
    func aDeletedEntryReturnsToTheTemplate() async throws {
        let session = EditorSession(
            files: ["2026/03/2026-03-01.md": "Walked to the market.\n"],
            settings: JournalSettings(contentTemplate: "# {{title}}\n")
        )
        await session.open()

        try await session.store.somebodyElseTakesAway("2026/03/2026-03-01.md")
        await session.editor.reloadIfClean()

        // The folder is the journal: with no file there, this is a day that
        // has not been written on, and it is the template that says so
        // (ADR 0001).
        #expect(session.editor.content == "# 2026-03-01\n")
        // And it stays that way — the spawned text is not a file, so nothing
        // puts the day back until somebody types.
        #expect(session.store.writes.isEmpty)
        #expect(try await session.store.listFiles() == ["Archive/moved-away.md"])
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
