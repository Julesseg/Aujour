import Foundation
import Testing
import AujourCore

@testable import Aujour

// The two ends of the settings seam, as the app actually has them: iCloud
// key-value storage for the settings that shape the Journal, `UserDefaults`
// for the ones that belong to this device (ADR 0003). Core knows only that
// settings are a bag of strings — which key means what, and what a default
// is, is proved there — so what is left here is the half only a device has:
// values that reach both stores, values that arrive from another device, and
// an iCloud that is not there at all.
//
// The iCloud side is a stand-in and not the real store, because the real one
// answers nothing without the `com.apple.developer.ubiquity-kvstore-identifier`
// entitlement and the test host is built unsigned. The device side is a real
// `UserDefaults` suite of the test's own — never `.standard`, which on a
// developer's Mac is the settings of their own Aujour.

@MainActor
@Suite("Where the settings live")
struct SettingsSeamTests {
    @Test("a setting written here is on this device and on its way to the others")
    func writesGoToBothSides() async throws {
        try await withADeviceOfItsOwn { onThisDevice in
            let iCloud = AnICloudThatAnswers()
            let settings = JournalSettingsStore(
                syncedThrough: SyncedSettingsStorage(iCloud: iCloud, onThisDevice: onThisDevice)
            )

            settings.update { $0.contentTemplate = "## Morning\n\n## Evening\n" }

            #expect(iCloud.stored["aujour.journal.contentTemplate"] == "## Morning\n\n## Evening\n")
            #expect(
                onThisDevice.string(forKey: "aujour.journal.contentTemplate")
                    == "## Morning\n\n## Evening\n"
            )
        }
    }

    @Test("a setting iCloud has not answered with yet is the one this device last saw")
    func readsFallBackToTheDevice() async throws {
        try await withADeviceOfItsOwn { onThisDevice in
            // The install that has been running for months: the template is on
            // the device, and iCloud is holding nothing today — signed out, in
            // Airplane mode, or simply slow to come back.
            onThisDevice.set("[Journal]/YYYY-MM-DD", forKey: "aujour.journal.pathTemplate")
            let settings = JournalSettingsStore(
                syncedThrough: SyncedSettingsStorage(
                    iCloud: AnICloudThatAnswers(),
                    onThisDevice: onThisDevice
                )
            )

            #expect(settings.settings.pathTemplate == "[Journal]/YYYY-MM-DD")
        }
    }

    @Test("what iCloud is holding wins over what this device last saw")
    func readsPreferICloud() async throws {
        try await withADeviceOfItsOwn { onThisDevice in
            onThisDevice.set("YYYY/MM/YYYY-MM-DD", forKey: "aujour.journal.pathTemplate")
            let iCloud = AnICloudThatAnswers()
            iCloud.stored["aujour.journal.pathTemplate"] = "[Journal]/YYYY-MM-DD"

            let settings = JournalSettingsStore(
                syncedThrough: SyncedSettingsStorage(iCloud: iCloud, onThisDevice: onThisDevice)
            )

            #expect(settings.settings.pathTemplate == "[Journal]/YYYY-MM-DD")
        }
    }

    @Test("a setting cleared is cleared on both sides, not left behind on one")
    func clearingRemovesItFromBothSides() async throws {
        try await withADeviceOfItsOwn { onThisDevice in
            let iCloud = AnICloudThatAnswers()
            let settings = JournalSettingsStore(
                syncedThrough: SyncedSettingsStorage(iCloud: iCloud, onThisDevice: onThisDevice)
            )
            settings.update { $0.contentTemplate = "## Morning\n" }

            // The one journal-shaping setting whose empty value is a real
            // value: no template at all, and a blank first page.
            settings.update { $0.contentTemplate = "" }

            #expect(iCloud.stored["aujour.journal.contentTemplate"] == "")
            #expect(onThisDevice.string(forKey: "aujour.journal.contentTemplate") == "")

            // And a reminder time removed is removed: `nil` is a key that has
            // to go, not an empty string to be read back as a time.
            let device = DeviceSettingsStore(storedOn: LocalSettingsStorage(onThisDevice: onThisDevice))
            device.update { $0.dailyReminder = TimeOfDay(hour: 8, minute: 30) }
            device.update { $0.dailyReminder = nil }
            #expect(onThisDevice.object(forKey: "aujour.device.dailyReminder") == nil)
        }
    }

    @Test("a setting changed on another device lands here, is kept, and is announced")
    func arrivalsAreKeptAndAnnounced() async throws {
        try await withADeviceOfItsOwn { onThisDevice in
            let iCloud = AnICloudThatAnswers()
            let seam = SyncedSettingsStorage(iCloud: iCloud, onThisDevice: onThisDevice)
            let settings = JournalSettingsStore(syncedThrough: seam)
            // A second listener, to prove that registering one never silences
            // another: the screen and the journal both watch these.
            var alsoHeard = 0
            seam.observeExternalChanges { alsoHeard += 1 }

            iCloud.theIPadWrites(["aujour.journal.rolloverHour": "4"])
            try await untilTheSettingsSay(4, in: settings)

            #expect(settings.settings.rolloverHour == RolloverHour(hour: 4))
            #expect(alsoHeard == 1)
            // Kept, so that it outlives the next time iCloud is unreachable —
            // a Rollover Hour that vanished because the network did would move
            // somebody's day underneath them.
            #expect(onThisDevice.string(forKey: "aujour.journal.rolloverHour") == "4")
        }
    }

    @Test("without the iCloud entitlement the settings are this device's alone, and work")
    func anUnentitledBuildFallsBackToTheDeviceAndNeverCrashes() async throws {
        try await withADeviceOfItsOwn { onThisDevice in
            // What an unsigned build has: a store that refuses, because there
            // is no `com.apple.developer.ubiquity-kvstore-identifier` to read
            // it with. This is every simulator build the CI job makes.
            let unentitled = AnICloudThatAnswers()
            unentitled.reachable = false

            let settings = JournalSettingsStore(
                syncedThrough: SyncedSettingsStorage(
                    iCloud: unentitled,
                    onThisDevice: onThisDevice
                )
            )
            // The defaults, and not a crash.
            #expect(settings.settings == .default)

            settings.update { $0.rolloverHour = RolloverHour(hour: 4)! }

            // Every setting still works; none of them travels.
            #expect(settings.settings.rolloverHour == RolloverHour(hour: 4))
            #expect(onThisDevice.string(forKey: "aujour.journal.rolloverHour") == "4")
            #expect(unentitled.stored.isEmpty)

            // And it is still there on the next launch, which is what makes
            // an unsigned build a usable app rather than one that forgets.
            let afterARelaunch = JournalSettingsStore(
                syncedThrough: SyncedSettingsStorage(iCloud: nil, onThisDevice: onThisDevice)
            )
            #expect(afterARelaunch.settings.rolloverHour == RolloverHour(hour: 4))
        }
    }

    @Test("a device-local setting stays on this device and survives a relaunch")
    func deviceSettingsAreKeptOnThisDevice() async throws {
        try await withADeviceOfItsOwn { onThisDevice in
            let device = DeviceSettingsStore(
                storedOn: LocalSettingsStorage(onThisDevice: onThisDevice)
            )

            device.update {
                $0.theme = .dark
                $0.editorFont = EditorFont(family: .serif, size: 19)
            }

            #expect(onThisDevice.string(forKey: "aujour.device.theme") == "dark")
            let afterARelaunch = DeviceSettingsStore(
                storedOn: LocalSettingsStorage(onThisDevice: onThisDevice)
            )
            #expect(afterARelaunch.settings.theme == .dark)
            #expect(afterARelaunch.settings.editorFont.family == .serif)

            // And nowhere near the synced seam: what proves it is the type —
            // `DeviceSettingsStore` takes a `LocalKeyValueStore`, which
            // `SyncedSettingsStorage` deliberately is not — so the keys of a
            // theme cannot be among the ones an iPad reads.
            let iCloud = AnICloudThatAnswers()
            _ = JournalSettingsStore(
                syncedThrough: SyncedSettingsStorage(iCloud: iCloud, onThisDevice: onThisDevice)
            )
            #expect(iCloud.stored.isEmpty)
        }
    }

    @Test("the appearance this device is drawn in is the one it was left in")
    func theAppearanceIsRead() async throws {
        try await withADeviceOfItsOwn { onThisDevice in
            onThisDevice.set("dark", forKey: "aujour.device.theme")
            let store = DeviceSettingsStore(
                storedOn: LocalSettingsStorage(onThisDevice: onThisDevice)
            )

            let appearance = DeviceAppearance(settings: store)
            #expect(appearance.colorScheme == .dark)

            // And it follows the setting rather than reading it once: nothing
            // has relaunched here.
            store.update { $0.theme = .system }
            #expect(appearance.colorScheme == nil)
        }
    }

    /// Waits for a Rollover Hour to have arrived from another device.
    ///
    /// iCloud says so on a notification, and what the app does about it is a
    /// hop to the main actor — so there is a moment, exactly as there is in
    /// the app, where the setting is still the old one.
    private func untilTheSettingsSay(
        _ hour: Int,
        in settings: JournalSettingsStore
    ) async throws {
        for _ in 0..<100 {
            if settings.settings.rolloverHour.hour == hour { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("the Rollover Hour never arrived — it is \(settings.settings.rolloverHour.hour)")
    }
}
