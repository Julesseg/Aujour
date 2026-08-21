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
        }

        // A second store over the same seam is the other device: it sees
        // everything, and nothing was lost or reshaped on the way through.
        let otherDevice = JournalSettingsStore(syncedThrough: kvs)
        #expect(otherDevice.settings == thisDevice.settings)
        #expect(otherDevice.settings.rolloverHour == RolloverHour(hour: 4)!)
        #expect(otherDevice.settings.embedSyntax == .obsidianWikiLink)
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
