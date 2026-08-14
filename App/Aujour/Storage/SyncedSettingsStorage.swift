import Foundation
import AujourCore

/// Where the journal-shaping settings actually live: iCloud key-value
/// storage, mirrored on the device (ADR 0003).
///
/// An iPhone and an iPad with different Path Templates would write the same
/// day to two paths and break the one-Entry-per-day rule, so these settings
/// have to be the same on both — and they travel through iCloud rather than
/// through a config file in the Journal Root, which is somebody's Obsidian
/// vault and is meant to hold Entries and nothing else.
///
/// Two stores rather than one, and it matters which is read: iCloud's is the
/// one that carries a change between devices, and the device's is the one
/// that is still there when iCloud is not — signed out, in Airplane mode, or
/// on the first launch after an install where the values have not come down
/// yet. So writes go to both, and a read prefers iCloud and falls back to the
/// device. A Path Template that vanished because the network did would move
/// somebody's journal underneath them.
///
/// Nothing here is a file in the Journal Root. That is the whole point of the
/// ADR, and `FileSystemPurityTests` is what keeps the domain side of it
/// honest.
@MainActor
final class SyncedSettingsStorage: SyncedKeyValueStore {
    /// iCloud's copy, or `nil` where there is deliberately not to be one —
    /// the UI suite, which cannot have one test's settings arriving in the
    /// next test's app.
    private let iCloud: NSUbiquitousKeyValueStore?

    /// This device's copy: what a read falls back to, and what makes a
    /// setting survive a relaunch on its own.
    private let onThisDevice: UserDefaults

    private var handlers: [() -> Void] = []

    /// The registration that has to be undone when this store goes, since a
    /// block-based observer outlives the object that made it. Unsafe by
    /// declaration only: it is written once here and read once in `deinit`,
    /// which cannot run while anything else is using it.
    private nonisolated(unsafe) var listeningForArrivals: (any NSObjectProtocol)?

    init(
        iCloud: NSUbiquitousKeyValueStore? = .default,
        onThisDevice: UserDefaults = .standard
    ) {
        self.iCloud = iCloud
        self.onThisDevice = onThisDevice

        guard let iCloud else { return }
        listeningForArrivals = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloud,
            queue: .main
        ) { [weak self] _ in
            // Hopped rather than assumed: the queue says main thread, which
            // is not by itself the main actor.
            Task { @MainActor in self?.somethingArrivedFromAnotherDevice() }
        }
        // Asks iCloud for whatever it is holding, so that the first read of a
        // fresh install is the user's settings rather than the defaults.
        iCloud.synchronize()
    }

    deinit {
        if let listeningForArrivals {
            NotificationCenter.default.removeObserver(listeningForArrivals)
        }
    }

    func string(forKey key: String) -> String? {
        iCloud?.string(forKey: key) ?? onThisDevice.string(forKey: key)
    }

    func setString(_ value: String?, forKey key: String) {
        // The device first, so that a value is durable here before it is
        // announced anywhere: a write that reached iCloud and not the disk
        // would be a setting this device forgets the moment it is offline.
        onThisDevice.set(value, forKey: key)
        guard let iCloud else { return }
        if let value {
            iCloud.set(value, forKey: key)
        } else {
            iCloud.removeObject(forKey: key)
        }
    }

    func observeExternalChanges(_ handler: @escaping () -> Void) {
        handlers.append(handler)
    }

    /// A write from another device has landed. What arrived is copied onto
    /// this device — so that it outlives the next time iCloud is unreachable
    /// — and then announced.
    private func somethingArrivedFromAnotherDevice() {
        if let iCloud {
            for (key, value) in iCloud.dictionaryRepresentation {
                guard let text = value as? String else { continue }
                onThisDevice.set(text, forKey: key)
            }
        }
        for handler in handlers { handler() }
    }
}
