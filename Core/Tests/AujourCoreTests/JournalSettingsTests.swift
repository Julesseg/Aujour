import Foundation
import Testing
@testable import AujourCore

@MainActor
@Suite("JournalSettings defaults")
struct JournalSettingsDefaultsTests {
    @Test("an empty seam yields the decision-log defaults")
    func defaultsMatchTheDecisionLog() {
        let settings = JournalSettingsStore(syncedThrough: InMemorySyncedKeyValueStore()).settings

        #expect(settings.pathTemplate == "YYYY/MM/YYYY-MM-DD")
        #expect(settings.attachmentPathTemplate == "[attachments]/YYYY/MM")
        #expect(settings.rolloverHour == .midnight)
        #expect(settings.embedSyntax == .standardMarkdown)
        // Obsidian ships no daily-note template either: a new Entry is blank
        // until the user points at a file to spawn from.
        #expect(settings.contentTemplateFile.isEmpty)
        // Events are a list, reminders are a task list, and a day with
        // nothing in it leaves nothing behind.
        #expect(settings.dataPlaceholders == .default)
        #expect(settings.dataPlaceholders[.reminders].linePrefix == "- [ ] ")
        #expect(settings.dataPlaceholders[.reminders].donePrefix == "- [x] ")
        #expect(settings.dataPlaceholders[.events].whenEmpty.isEmpty)
    }

    @Test("an unreadable value falls back to that field's default, leaving the others intact")
    func onlyTheCorruptFieldFallsBack() {
        let kvs = InMemorySyncedKeyValueStore()
        kvs.receiveFromAnotherDevice([
            JournalSettingsKey.pathTemplate: "[journal]/YYYY-MM-DD",
            JournalSettingsKey.rolloverHour: "99",
            JournalSettingsKey.embedSyntax: "hieroglyphs",
        ])

        let settings = JournalSettingsStore(syncedThrough: kvs).settings

        #expect(settings.pathTemplate == "[journal]/YYYY-MM-DD")
        #expect(settings.rolloverHour == .midnight)
        #expect(settings.embedSyntax == .standardMarkdown)
    }

    @Test("an empty path template is not a template, so the default stands")
    func emptyTemplatesFallBack() {
        let kvs = InMemorySyncedKeyValueStore()
        kvs.receiveFromAnotherDevice([
            JournalSettingsKey.pathTemplate: "",
            JournalSettingsKey.attachmentPathTemplate: "",
            JournalSettingsKey.contentTemplateFile: "",
        ])

        let settings = JournalSettingsStore(syncedThrough: kvs).settings

        // An empty Path Template would name every Entry `.md`; no Content
        // Template file at all is simply a blank new Entry, which is
        // legitimate.
        #expect(settings.pathTemplate == JournalSettings.default.pathTemplate)
        #expect(settings.attachmentPathTemplate == JournalSettings.default.attachmentPathTemplate)
        #expect(settings.contentTemplateFile.isEmpty)
    }
}

@MainActor
@Suite("JournalSettings sync seam")
struct JournalSettingsSyncTests {
    @Test("journal-shaping settings round-trip through the seam")
    func journalShapingSettingsRoundTrip() {
        let kvs = InMemorySyncedKeyValueStore()
        let thisDevice = JournalSettingsStore(syncedThrough: kvs)

        thisDevice.update {
            $0.pathTemplate = "[journal]/YYYY-MM-DD"
            $0.contentTemplateFile = "templates/Daily.md"
            $0.attachmentPathTemplate = "[media]/YYYY"
            $0.embedSyntax = .obsidianWikiLink
            $0.rolloverHour = RolloverHour(hour: 4)!
            $0.dataPlaceholders[.events].linePrefix = "* "
            $0.dataPlaceholders[.events].whenEmpty = "_a quiet day_"
            $0.dataPlaceholders[.reminders].timeFormat = nil
        }

        // A second store over the same seam is the other device: it sees
        // everything, and nothing was lost or reshaped on the way through.
        let otherDevice = JournalSettingsStore(syncedThrough: kvs)
        #expect(otherDevice.settings == thisDevice.settings)
        #expect(otherDevice.settings.rolloverHour == RolloverHour(hour: 4)!)
        #expect(otherDevice.settings.embedSyntax == .obsidianWikiLink)
        // Including the one stored as an empty value: "leave the times out"
        // has to survive the trip as itself and not as the default it looks
        // like an absence of.
        #expect(otherDevice.settings.dataPlaceholders[.reminders].timeFormat == nil)
        #expect(otherDevice.settings.dataPlaceholders[.events].whenEmpty == "_a quiet day_")
    }

    @Test("a data placeholder's formatting is one key per field, like the rest")
    func dataPlaceholderFieldsAreWrittenSeparately() {
        let kvs = InMemorySyncedKeyValueStore()
        let store = JournalSettingsStore(syncedThrough: kvs)

        store.update { $0.dataPlaceholders[.events].whenEmpty = "_nothing today_" }

        // So that an iPad changing how reminders read, at the same moment,
        // still has changed how reminders read (ADR 0003).
        #expect(kvs.writtenKeys == [JournalSettingsKey.dataPlaceholder(.events).whenEmpty])
    }

    @Test("an unreadable data-placeholder field leaves the others standing")
    func oneCorruptDataFieldFallsBackAlone() {
        let kvs = InMemorySyncedKeyValueStore()
        kvs.receiveFromAnotherDevice([
            JournalSettingsKey.dataPlaceholder(.events).linePrefix: "* ",
            // Not a Moment format anybody meant, which Moment renders as the
            // literal text it is — never a reason to lose the line prefix
            // beside it.
            JournalSettingsKey.dataPlaceholder(.events).timeFormat: "!!!",
        ])

        let settings = JournalSettingsStore(syncedThrough: kvs).settings

        #expect(settings.dataPlaceholders[.events].linePrefix == "* ")
        #expect(settings.dataPlaceholders[.events].timeFormat == MomentFormat("!!!"))
        #expect(settings.dataPlaceholders[.reminders] == .default(for: .reminders))
    }

    @Test("only the fields that changed are written, so another device's edits survive")
    func untouchedFieldsAreNotRewritten() {
        let kvs = InMemorySyncedKeyValueStore()
        let store = JournalSettingsStore(syncedThrough: kvs)

        store.update { $0.rolloverHour = RolloverHour(hour: 4)! }

        // iCloud key-value storage is last-writer-wins per key (ADR 0003):
        // rewriting untouched keys would stamp on the other device's edits.
        #expect(kvs.writtenKeys == [JournalSettingsKey.rolloverHour])
    }

    @Test("an update that changes nothing writes nothing and notifies nobody")
    func noOpUpdateIsSilent() {
        let kvs = InMemorySyncedKeyValueStore()
        let store = JournalSettingsStore(syncedThrough: kvs)
        let observed = ObservedSettings()
        store.observe { observed.record($0) }

        store.update { $0.rolloverHour = .midnight }

        #expect(kvs.writtenKeys.isEmpty)
        #expect(observed.updates.isEmpty)
    }

    @Test("a write from another device surfaces as an observable update")
    func externalWriteSurfacesAsAnUpdate() {
        let kvs = InMemorySyncedKeyValueStore()
        let store = JournalSettingsStore(syncedThrough: kvs)
        let observed = ObservedSettings()
        store.observe { observed.record($0) }

        kvs.receiveFromAnotherDevice([JournalSettingsKey.pathTemplate: "[journal]/YYYY-MM-DD"])

        #expect(store.settings.pathTemplate == "[journal]/YYYY-MM-DD")
        #expect(observed.updates.map(\.pathTemplate) == ["[journal]/YYYY-MM-DD"])
    }

    @Test("an external write of the values we already hold notifies nobody")
    func redundantExternalWriteIsSilent() {
        let kvs = InMemorySyncedKeyValueStore()
        let store = JournalSettingsStore(syncedThrough: kvs)
        store.update { $0.rolloverHour = RolloverHour(hour: 4)! }
        let observed = ObservedSettings()
        store.observe { observed.record($0) }

        kvs.receiveFromAnotherDevice([JournalSettingsKey.rolloverHour: "4"])

        #expect(observed.updates.isEmpty)
    }

    @Test("a local edit notifies observers, so one update path drives the UI")
    func localEditNotifiesObservers() {
        let store = JournalSettingsStore(syncedThrough: InMemorySyncedKeyValueStore())
        let observed = ObservedSettings()
        store.observe { observed.record($0) }

        store.update { $0.embedSyntax = .obsidianWikiLink }

        #expect(observed.updates.map(\.embedSyntax) == [.obsidianWikiLink])
    }

    @Test("a second store over the same seam does not silence the first")
    func everyStoreOnTheSeamHearsExternalWrites() {
        let kvs = InMemorySyncedKeyValueStore()
        let first = JournalSettingsStore(syncedThrough: kvs)
        let second = JournalSettingsStore(syncedThrough: kvs)

        kvs.receiveFromAnotherDevice([JournalSettingsKey.pathTemplate: "[journal]/YYYY-MM-DD"])

        #expect(first.settings.pathTemplate == "[journal]/YYYY-MM-DD")
        #expect(second.settings.pathTemplate == "[journal]/YYYY-MM-DD")
    }

    @Test("a cancelled observation stops receiving updates")
    func cancelledObservationGoesQuiet() {
        let kvs = InMemorySyncedKeyValueStore()
        let store = JournalSettingsStore(syncedThrough: kvs)
        let observed = ObservedSettings()
        let observation = store.observe { observed.record($0) }

        observation.cancel()
        kvs.receiveFromAnotherDevice([JournalSettingsKey.pathTemplate: "[journal]/YYYY-MM-DD"])

        #expect(observed.updates.isEmpty)
    }
}

/// Collects what an observer was told, so a test can assert on the sequence.
@MainActor
final class ObservedSettings {
    private(set) var updates: [JournalSettings] = []

    func record(_ settings: JournalSettings) {
        updates.append(settings)
    }
}

/// The Rollover Hour as a thing to say out loud.
///
/// One screen sets it and another names it — the page over a day that has not
/// arrived says when writing opens on it — and the two have to say the same
/// hour in the same words, which is what having one of these rather than two
/// clock formatters is for.
///
/// Asked about the conventions and not about the punctuation. Which character
/// sits between the minutes and the "AM" is ICU's business and it has changed
/// under this app before; whether the reader is shown a 12-hour clock is not.
@Suite("The Rollover Hour, spelled out")
struct RolloverHourSpellingTests {
    private let english = Locale(identifier: "en_US")
    private let french = Locale(identifier: "fr_FR")

    @Test("it is written on a 12-hour clock for a reader whose region is on one")
    func itFollowsTheReadersClock() {
        let fourInTheMorning = RolloverHour(hour: 4)!.spelledOut(locale: english)

        #expect(fourInTheMorning.hasPrefix("4:00"))
        #expect(fourInTheMorning.contains("AM"))
    }

    /// The default, and the hour the two conventions disagree about most:
    /// midnight is the twelfth hour on one clock and the zeroth on the other.
    @Test("and on a 24-hour clock for a reader whose region is on that")
    func aFrenchClockHasNoMeridiem() {
        #expect(RolloverHour(hour: 13)!.spelledOut(locale: french).hasPrefix("13:00"))
        #expect(!RolloverHour.midnight.spelledOut(locale: french).contains("AM"))
        #expect(RolloverHour.midnight.spelledOut(locale: english).contains("12:00"))
    }

    /// The claim that matters more than either spelling: the hour a day turns
    /// at is written by the same clock face as every other time in the app,
    /// so the settings row and the locked page cannot come to disagree.
    @Test("every hour is the clock face the rest of the app writes")
    func everyHourIsTheAppsOwnClockFace() {
        for hour in 0..<24 {
            #expect(
                RolloverHour(hour: hour)!.spelledOut(locale: english)
                    == TimeOfDay(hour: hour, minute: 0)!.spelledOut(locale: english)
            )
        }
    }

    /// Measured off a day with no daylight saving in it, like every other
    /// clock face in the app: no two hours of the day may come out saying the
    /// same thing, which is what an hour hung off a real date does twice a
    /// year.
    @Test("no two hours of the day are written the same way")
    func everyHourIsItsOwn() {
        let spellings = (0..<24).map { RolloverHour(hour: $0)!.spelledOut(locale: english) }

        #expect(Set(spellings).count == 24)
    }
}

extension RolloverHourSpellingTests {
    /// What the screen that offers them counts through, so it never has to
    /// deal with an hour there is no such thing as.
    @Test("there are twenty-four hours a day could turn at, in order")
    func everyHourOfTheDayIsThere() {
        #expect(RolloverHour.everyHourOfTheDay.map(\.hour) == Array(0..<24))
        #expect(RolloverHour.everyHourOfTheDay.first == .midnight)
    }
}
