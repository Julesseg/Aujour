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
    /// Registers the handler called when values arrive from another device.
    /// One handler per store: the settings store that owns the seam.
    func observeExternalChanges(_ handler: @escaping () -> Void)
}

/// A key-value store that stays on this device — backed by `UserDefaults` in
/// the app. Device-scoped preferences (theme, fonts, notification time) are
/// kept here, and the type is what stops them reaching the synced seam.
@MainActor
public protocol LocalKeyValueStore: KeyValueStore {}

/// The storage half of the in-memory fakes: a dictionary that remembers the
/// order in which keys were written.
@MainActor
struct RecordingKeyValueStorage {
    private var values: [String: String] = [:]
    private(set) var writtenKeys: [String] = []

    func string(forKey key: String) -> String? {
        values[key]
    }

    mutating func setString(_ value: String?, forKey key: String) {
        values[key] = value
        writtenKeys.append(key)
    }

    mutating func merge(_ incoming: [String: String]) {
        values.merge(incoming) { _, new in new }
    }
}

/// An in-memory stand-in for iCloud key-value storage, for tests and previews.
@MainActor
public final class InMemorySyncedKeyValueStore: SyncedKeyValueStore {
    private var storage = RecordingKeyValueStorage()
    private var externalChangeHandler: (() -> Void)?

    public init() {}

    /// The keys written through this store, oldest first — so a test can say
    /// what did *not* travel as precisely as what did.
    public var writtenKeys: [String] { storage.writtenKeys }

    public func string(forKey key: String) -> String? {
        storage.string(forKey: key)
    }

    public func setString(_ value: String?, forKey key: String) {
        storage.setString(value, forKey: key)
    }

    public func observeExternalChanges(_ handler: @escaping () -> Void) {
        externalChangeHandler = handler
    }

    /// Plays another device's write into the seam: the values land, then the
    /// change is announced, exactly as iCloud does it.
    public func receiveFromAnotherDevice(_ values: [String: String]) {
        storage.merge(values)
        externalChangeHandler?()
    }
}

/// An in-memory stand-in for on-device storage, for tests and previews.
@MainActor
public final class InMemoryLocalKeyValueStore: LocalKeyValueStore {
    private var storage = RecordingKeyValueStorage()

    public init() {}

    /// The keys written through this store, oldest first.
    public var writtenKeys: [String] { storage.writtenKeys }

    public func string(forKey key: String) -> String? {
        storage.string(forKey: key)
    }

    public func setString(_ value: String?, forKey key: String) {
        storage.setString(value, forKey: key)
    }
}
