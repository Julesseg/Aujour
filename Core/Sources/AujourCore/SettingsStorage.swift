/// A group of settings that persists as one key per field.
///
/// One key per field rather than a single blob, because key-value storage is
/// last-writer-wins per key (ADR 0003): a phone changing the Rollover Hour
/// while an iPad changes the Content Template should leave both edits alive.
/// Reading is total — every field falls back to its own default rather than
/// failing — so one hand-edited or future-version value can never take the
/// rest of the settings down with it.
protocol SettingsGroup: Equatable, Sendable {
    static var `default`: Self { get }

    /// Reads a group from stored values, looked up by key.
    init(storedValues: (String) -> String?)

    /// The stored representations that differ from `previous`, in field
    /// order. A `nil` value means the key should be cleared.
    func changedValues(from previous: Self) -> [(key: String, value: String?)]
}

/// Keeps a settings group in step with a key-value store, and tells whoever
/// is listening when it changes.
///
/// The public stores (`JournalSettingsStore`, `DeviceSettingsStore`) are thin
/// skins over this: all they add is which kind of key-value store they accept,
/// which is what keeps device-local settings off the synced seam.
@MainActor
final class SettingsStorage<Group: SettingsGroup> {
    private let store: any KeyValueStore
    private(set) var value: Group

    private var observers: [Int: (Group) -> Void] = [:]
    private var nextObserverID = 0

    init(store: any KeyValueStore) {
        self.store = store
        self.value = Group(storedValues: { store.string(forKey: $0) })
    }

    /// Applies an edit, persisting only the fields it actually changed.
    func update(_ change: (inout Group) -> Void) {
        var updated = value
        change(&updated)
        guard updated != value else { return }

        for changed in updated.changedValues(from: value) {
            store.setString(changed.value, forKey: changed.key)
        }
        adopt(updated)
    }

    /// Re-reads the store after it changed underneath us — another device's
    /// write arriving through the synced seam.
    func reloadFromStore() {
        adopt(Group(storedValues: { [store] in store.string(forKey: $0) }))
    }

    @discardableResult
    func observe(_ handler: @escaping (Group) -> Void) -> SettingsObservation {
        let id = nextObserverID
        nextObserverID += 1
        observers[id] = handler
        return SettingsObservation { [weak self] in self?.observers[id] = nil }
    }

    /// Settling on a value: observers hear about it only if it is news, so a
    /// redundant write — from this device or another — stays quiet.
    private func adopt(_ updated: Group) {
        guard updated != value else { return }
        value = updated
        for observer in observers.values { observer(updated) }
    }
}

/// A registered settings observer, live until it is cancelled.
@MainActor
public final class SettingsObservation {
    private var cancelObservation: (() -> Void)?

    init(cancel: @escaping () -> Void) {
        self.cancelObservation = cancel
    }

    /// Stops delivery. Cancelling twice is harmless.
    public func cancel() {
        cancelObservation?()
        cancelObservation = nil
    }
}
