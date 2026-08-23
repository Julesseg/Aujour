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

        removeTheFolderItJournaledInto(journal)
    }

    @Test("the day a test seeded is what the data placeholders spawn from")
    func seededItemsReachTheSpawnedEntry() async throws {
        let journal = try #require(
            UITestingJournal.fromLaunchEnvironment([
                UITestingJournal.folderKey: "AJournalWithACalendar",
                UITestingJournal.contentTemplateKey: "## Today\n{{events}}\n\n## To do\n{{reminders}}",
                UITestingJournal.eventsKey: "09:30 Standup\nBank holiday",
                UITestingJournal.remindersKey: "18:00 Bread",
            ])
        )

        await journal.open()

        let editor = try #require(journal.today)
        // Times where a line carried one, none where it did not — and never
        // this machine's own calendar, which is the point of seeding at all.
        #expect(
            editor.content
                == "## Today\n- 09:30 Standup\n- Bank holiday\n\n## To do\n- [ ] 18:00 Bread"
        )

        removeTheFolderItJournaledInto(journal)
    }

    // The other seam a UI test stands in for: where the device is. Seeded as
    // lines so that a suite can say what a {{location}} widget will offer, and
    // read back here because the parsing is the one part of it that is neither
    // a screen nor a device.
    @Test("the places a test seeded are what the location widget is offered")
    func seededPlacesReachTheWidget() async throws {
        let journal = try #require(
            UITestingJournal.fromLaunchEnvironment([
                UITestingJournal.folderKey: "AJournalSomewhere",
                UITestingJournal.placesKey:
                    "Cafe de Flore | Boulevard Saint-Germain\nLes Deux Magots\n",
            ])
        )

        let around = await journal.places.around()

        #expect(around.toOffer.map(\.name) == ["Cafe de Flore", "Les Deux Magots"])
        #expect(around.named.first?.place.region == "Boulevard Saint-Germain")
        // A line with no `|` is a place with nothing under its name in the
        // picker, not a place called "Les Deux Magots | ".
        #expect(around.named.last?.place.region == nil)
    }

    // The permission the suite says, and what it costs: a refused device is
    // never read, so the widget offers nothing and asks nobody anything.
    @Test("a launch that refused the location permission offers no places")
    func refusedPlacesOfferNothing() async throws {
        let journal = try #require(
            UITestingJournal.fromLaunchEnvironment([
                UITestingJournal.folderKey: "AJournalNowhere",
                UITestingJournal.placesKey: "Cafe de Flore",
                UITestingJournal.placesAccessKey: "refused",
            ])
        )

        #expect(journal.places.access == .refused)
        #expect(await journal.places.around().toOffer.isEmpty)
    }

    // And the default: a launch that said nothing about the device is allowed
    // to read one, and reads a device with nowhere on it. That is what keeps
    // every other test in the suite free of a location permission without
    // reaching CoreLocation for any of them.
    @Test("a launch that seeded no places reads a device with nowhere on it")
    func noPlacesSeeded() async throws {
        let journal = try #require(
            UITestingJournal.fromLaunchEnvironment([
                UITestingJournal.folderKey: "AJournalWithNoPlaces"
            ])
        )

        #expect(journal.places.access == .allowed)
        #expect(await journal.places.around().toOffer.isEmpty)
    }

    @Test("a launch that seeded no calendar spawns the placeholders empty")
    func anUnseededCalendarIsAnEmptyDay() async throws {
        let journal = try #require(
            UITestingJournal.fromLaunchEnvironment([
                UITestingJournal.folderKey: "AJournalWithNoCalendar",
                UITestingJournal.contentTemplateKey: "a{{events}}b",
            ])
        )

        await journal.open()

        // Empty, and without EventKit having been asked anything — a UI test
        // that stopped for a permission alert would stop for it every time.
        #expect(try #require(journal.today).content == "ab")

        removeTheFolderItJournaledInto(journal)
    }

    /// A test's journal folder is inside the app's own Documents, which
    /// outlives the test — so each one takes its folder away with it, or the
    /// next run opens a journal the last one wrote.
    private func removeTheFolderItJournaledInto(_ journal: Journal) {
        guard case .open(let root, _) = journal.state else { return }
        try? FileManager.default.removeItem(at: root.url)
    }
}
