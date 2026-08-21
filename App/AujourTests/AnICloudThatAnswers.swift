import Foundation
import AujourCore

@testable import Aujour

// The stand-ins the settings seam is tested through, shared by every suite
// that needs one: storage of this test's own on both sides.

/// Runs a test against `UserDefaults` of its own, emptied afterwards.
///
/// Never `.standard`: these tests run on a machine that has an Aujour of its
/// own, and a test that wrote a Content Template into the standard suite would
/// be writing into somebody's real journal settings.
@MainActor
func withADeviceOfItsOwn<T>(
    _ body: (UserDefaults) async throws -> T
) async rethrows -> T {
    let name = "aujour.tests.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { UserDefaults.standard.removePersistentDomain(forName: name) }
    return try await body(suite)
}

/// iCloud key-value storage as a test can have it: the real one holds nothing
/// on an unsigned build, so a test that wanted to watch a setting arrive from
/// another device would be watching a store that never answers.
///
/// Behaves the way `NSUbiquitousKeyValueStore` does, including the way it
/// behaves when the app was built without the
/// `com.apple.developer.ubiquity-kvstore-identifier` entitlement: there is
/// still a store, and it answers nothing, keeps nothing, and syncs nothing.
final class AnICloudThatAnswers: ICloudKeyValueStore {
    /// What iCloud is holding — seeded directly for the settings another
    /// device left there before this one launched.
    var stored: [String: String] = [:]

    /// Whether this build was entitled to reach iCloud at all. `false` is
    /// every unsigned build, the CI simulator among them.
    var entitled = true

    func string(forKey key: String) -> String? { entitled ? stored[key] : nil }

    func set(_ value: String?, forKey key: String) {
        guard entitled else { return }
        stored[key] = value
    }

    func removeObject(forKey key: String) {
        guard entitled else { return }
        stored[key] = nil
    }

    var dictionaryRepresentation: [String: Any] { entitled ? stored : [:] }

    @discardableResult
    func synchronize() -> Bool { entitled }

    /// Another device writes, and iCloud says so — values first and the
    /// notice after, which is the order the real one does it in.
    func theIPadWrites(_ values: [String: String]) {
        stored.merge(values) { _, new in new }
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self
        )
    }
}
