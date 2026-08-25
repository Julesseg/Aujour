import Foundation
import Testing
@testable import AujourCore

@MainActor
@Suite("Device-local settings")
struct DeviceSettingsTests {
    @Test("an empty store yields the device defaults")
    func defaults() {
        let settings = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore()).settings

        #expect(settings.theme == .system)
        #expect(settings.accent == .driftwood)
        #expect(settings.editorFont == .default)
        // "Off until a time is chosen in the welcome" — no reminder by default.
        #expect(settings.dailyReminder == nil)
        // And a device nobody has welcomed is owed one.
        #expect(!settings.hasBeenWelcomed)
    }

    @Test("device settings round-trip through local storage")
    func roundTrip() {
        let local = InMemoryLocalKeyValueStore()
        let store = DeviceSettingsStore(storedOn: local)

        store.update {
            $0.theme = .dark
            $0.accent = .olive
            $0.editorFont = EditorFont(family: .serif, size: .large)
            $0.dailyReminder = TimeOfDay(hour: 21, minute: 30)
            $0.hasBeenWelcomed = true
        }

        let afterRelaunch = DeviceSettingsStore(storedOn: local)
        #expect(afterRelaunch.settings == store.settings)
        #expect(afterRelaunch.settings.accent == .olive)
        #expect(afterRelaunch.settings.dailyReminder == TimeOfDay(hour: 21, minute: 30))
        // The claim the welcome rests on: it happens once per device, and the
        // device remembers across launches that it did.
        #expect(afterRelaunch.settings.hasBeenWelcomed)
    }

    @Test("changing device settings never touches the synced seam")
    func deviceSettingsNeverReachTheSyncedSeam() {
        let synced = InMemorySyncedKeyValueStore()
        let local = InMemoryLocalKeyValueStore()
        let journal = JournalSettingsStore(syncedThrough: synced)
        let device = DeviceSettingsStore(storedOn: local)

        device.update {
            $0.theme = .dark
            $0.accent = .clay
            $0.editorFont = EditorFont(family: .monospaced, size: .small)
            $0.dailyReminder = TimeOfDay(hour: 7, minute: 0)
            $0.hasBeenWelcomed = true
        }

        // Theme, fonts and notification time are device-scoped (ADR 0003):
        // nothing about them may travel to the user's other devices.
        #expect(synced.writtenKeys.isEmpty)
        #expect(journal.settings == JournalSettings.default)
        #expect(!local.writtenKeys.isEmpty)
    }

    @Test("an unreadable value falls back to that field's default, leaving the others intact")
    func onlyTheCorruptFieldFallsBack() {
        let local = InMemoryLocalKeyValueStore()
        local.setString("dark", forKey: DeviceSettingsKey.theme)
        local.setString("chartreuse", forKey: DeviceSettingsKey.accent)
        local.setString("chalkboard", forKey: DeviceSettingsKey.editorFontFamily)
        local.setString("enormous", forKey: DeviceSettingsKey.editorFontSize)
        local.setString("25:61", forKey: DeviceSettingsKey.dailyReminder)
        local.setString("perhaps", forKey: DeviceSettingsKey.hasBeenWelcomed)

        let settings = DeviceSettingsStore(storedOn: local).settings

        #expect(settings.theme == .dark)
        #expect(settings.accent == .driftwood)
        #expect(settings.editorFont == .default)
        #expect(settings.dailyReminder == nil)
        #expect(!settings.hasBeenWelcomed)
    }

    @Test("turning the daily reminder off clears it everywhere")
    func reminderCanBeTurnedOff() {
        let local = InMemoryLocalKeyValueStore()
        let store = DeviceSettingsStore(storedOn: local)
        store.update { $0.dailyReminder = TimeOfDay(hour: 21, minute: 30) }

        store.update { $0.dailyReminder = nil }

        #expect(DeviceSettingsStore(storedOn: local).settings.dailyReminder == nil)
    }

    @Test("a local edit notifies observers")
    func editsNotifyObservers() {
        let store = DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore())
        let observed = ObservedDeviceSettings()
        store.observe { observed.record($0) }

        store.update { $0.theme = .light }

        #expect(observed.updates.map(\.theme) == [.light])
    }
}

@MainActor
@Suite("Editor font")
struct EditorFontTests {
    @Test("the four steps are in the order they are offered in")
    func sizesAreOrdered() {
        // The screen offers them left to right and the order is the enum's:
        // a set that came out shuffled would be a size control nobody could
        // read.
        #expect(EditorFont.Size.allCases == [.small, .medium, .large, .extraLarge])
    }

    @Test("a step read back from storage is the step that was written")
    func sizesRoundTripByName() {
        // Stored by name and not by number, so a step whose point size is
        // retuned later is still the step the user chose.
        for size in EditorFont.Size.allCases {
            #expect(EditorFont.Size(rawValue: size.rawValue) == size)
        }
    }
}

@MainActor
@Suite("Time of day")
struct TimeOfDayTests {
    @Test("a time outside the clock is refused")
    func outOfRangeTimesAreRefused() {
        #expect(TimeOfDay(hour: 24, minute: 0) == nil)
        #expect(TimeOfDay(hour: 21, minute: 60) == nil)
        #expect(TimeOfDay(hour: -1, minute: 0) == nil)
        #expect(TimeOfDay(hour: 23, minute: 59) != nil)
    }
}

/// Collects what an observer was told, so a test can assert on the sequence.
@MainActor
final class ObservedDeviceSettings {
    private(set) var updates: [DeviceSettings] = []

    func record(_ settings: DeviceSettings) {
        updates.append(settings)
    }
}
