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
/// Where there is no iCloud to be had at all — a build with no
/// `com.apple.developer.ubiquity-kvstore-identifier` entitlement, which is
/// every unsigned simulator build — the device's copy is the whole of it. The
/// app is the same app: every setting reads, writes, and survives a relaunch;
/// the only thing missing is the travelling.
///
/// Nothing here is a file in the Journal Root. That is the whole point of the
/// ADR, and `FileSystemPurityTests` is what keeps the domain side of it
/// honest.
@MainActor
final class SyncedSettingsStorage: SyncedKeyValueStore {
    /// iCloud's copy, or `nil` where there is not one to be had: a build with
    /// no `com.apple.developer.ubiquity-kvstore-identifier` entitlement — an
    /// unsigned simulator build, which is what CI runs — or the UI suite,
    /// which asks for none deliberately, since one test's settings arriving in
    /// the next test's app is not a suite that can claim anything.
    ///
    /// Without it the settings are this device's alone: every one of them
    /// still works and still survives a relaunch, and none of them travels.
    private let iCloud: (any ICloudKeyValues)?

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
        iCloud: (any ICloudKeyValues)? = NSUbiquitousKeyValueStore.default,
        onThisDevice: UserDefaults = .standard
    ) {
        // Asked on the way in, for two answers at once. It brings down
        // whatever iCloud is already holding, so that the first read of a
        // fresh install is the user's settings rather than the defaults — and
        // it is the documented way to find out whether there is an entitlement
        // to reach iCloud with at all, since it answers `false` for an app
        // that was built without one. Asked once and not again: how the app
        // was signed does not change while it is running, and a launch is the
        // granularity anything else would wait for anyway.
        self.iCloud = iCloud.flatMap { $0.synchronize() ? $0 : nil }
        self.onThisDevice = onThisDevice

        guard let iCloud = self.iCloud else { return }
        listeningForArrivals = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloud,
            queue: .main
        ) { [weak self] _ in
            // Hopped rather than assumed: the queue says main thread, which
            // is not by itself the main actor.
            Task { @MainActor in self?.somethingArrivedFromAnotherDevice() }
        }
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
        //
        // A cleared setting is a key that goes, on both sides. Left behind on
        // either, it would be read back as a setting the user has turned off.
        if let value {
            onThisDevice.set(value, forKey: key)
        } else {
            onThisDevice.removeObject(forKey: key)
        }
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

/// iCloud key-value storage, as this file uses it.
///
/// A protocol rather than `NSUbiquitousKeyValueStore` itself because the real
/// store answers nothing without the
/// `com.apple.developer.ubiquity-kvstore-identifier` entitlement, and the test
/// host is built unsigned — so a test that wanted to watch a setting arrive
/// from another device would be watching a store that never holds anything.
protocol ICloudKeyValues: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    func removeObject(forKey key: String)

    /// Everything iCloud is holding — what a write arriving from another
    /// device is copied onto this device from.
    var dictionaryRepresentation: [String: Any] { get }

    /// Flushes what has been written, and says whether there was anywhere to
    /// flush it to: `false` where the app was built without the entitlement,
    /// which is what makes this the availability check as well.
    @discardableResult
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: ICloudKeyValues {}
