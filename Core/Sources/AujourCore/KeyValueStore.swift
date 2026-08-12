/// Somewhere small strings can be kept between launches.
///
/// This is the whole of Aujour's settings persistence: a bag of strings, with
/// no notion of a path or a file. Nothing here can reach the Journal Root,
/// which is the point — the folder holds Entries, Attachments and Parked
/// Files, never app configuration (ADR 0003).
@MainActor
public protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func setString(_ value: String?, forKey key: String)
}

/// A key-value store whose contents travel to the user's other devices —
/// backed by iCloud key-value storage in the app.
///
/// Journal-shaping settings live here so two devices cannot disagree about
/// where today's Entry belongs. Values may change underneath the app at any
/// moment, which is what `observeExternalChanges` reports.
@MainActor
public protocol SyncedKeyValueStore: KeyValueStore {
    /// Registers a handler called when values arrive from another device.
    /// Handlers accumulate: registering one never silences an earlier one.
    func observeExternalChanges(_ handler: @escaping () -> Void)
}

/// A key-value store that stays on this device — backed by `UserDefaults` in
/// the app. Device-scoped preferences (theme, fonts, notification time) are
/// kept here, and the type is what stops them reaching the synced seam.
@MainActor
public protocol LocalKeyValueStore: KeyValueStore {}

/// An in-memory stand-in for real storage, for tests and previews. Use one of
/// the two subclasses, which are what say whether values travel or not.
@MainActor
public class InMemoryKeyValueStore: KeyValueStore {
    private var values: [String: String] = [:]

    /// The keys written through this store, oldest first — so a test can say
    /// what did *not* travel as precisely as what did.
    public private(set) var writtenKeys: [String] = []

    public init() {}

    public func string(forKey key: String) -> String? {
        values[key]
    }

    public func setString(_ value: String?, forKey key: String) {
        values[key] = value
        writtenKeys.append(key)
    }

    /// Puts values in place without recording a write, for storage that was
    /// already populated when the app found it.
    fileprivate func adoptWithoutRecording(_ incoming: [String: String]) {
        values.merge(incoming) { _, new in new }
    }
}

/// An in-memory stand-in for iCloud key-value storage.
@MainActor
public final class InMemorySyncedKeyValueStore: InMemoryKeyValueStore, SyncedKeyValueStore {
    private var externalChangeHandlers: [() -> Void] = []

    public func observeExternalChanges(_ handler: @escaping () -> Void) {
        externalChangeHandlers.append(handler)
    }

    /// Plays another device's write into the seam: the values land, then the
    /// change is announced, exactly as iCloud does it.
    public func receiveFromAnotherDevice(_ values: [String: String]) {
        adoptWithoutRecording(values)
        for handler in externalChangeHandlers { handler() }
    }
}

/// An in-memory stand-in for on-device storage.
@MainActor
public final class InMemoryLocalKeyValueStore: InMemoryKeyValueStore, LocalKeyValueStore {}
