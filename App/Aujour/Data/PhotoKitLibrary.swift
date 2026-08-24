import Foundation
import Photos
import UIKit

import AujourCore

/// The user's photo library, as the suggestions panel reads it.
///
/// PhotoKit's half of ``AujourCore/PhotoLibrary``, and nothing besides: which
/// photographs belong to the day being written, whether the panel should be
/// there at all and what a tap does are all decided above this, over a library
/// that is said rather than read.
///
/// Stateless, so there is nothing to keep or to keep in step. A `PHFetchResult`
/// is a query answered lazily against the library's own index, and the image
/// manager is a shared one — holding either would only be holding something
/// that is already there.
///
/// ## Read access, asked for once, and for one thing only
///
/// The level asked for is `.readWrite`, which is the only one that can read a
/// library at all — `.addOnly` lets an app put photographs *in*, which Aujour
/// never does. Somebody who grants the limited-library subset has granted
/// access to exactly the photographs they picked, and that is an answer worth
/// having: the panel offers whichever of them fall on the day, and says
/// nothing about the rest.
struct PhotoKitLibrary: PhotoLibrary {
    var access: PhotoLibraryAccess {
        Self.standing(of: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func ask() async -> PhotoLibraryAccess {
        Self.standing(of: await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    /// Where a permission stands, as the panel means it.
    ///
    /// `.limited` is allowed, deliberately: the user picked out some
    /// photographs and those are the ones Aujour can see, which is a smaller
    /// library rather than a refused one. `.restricted` — a device managed so
    /// that nobody may allow it — is a refusal, because it is one that will
    /// never change by asking.
    private static func standing(of status: PHAuthorizationStatus) -> PhotoLibraryAccess {
        switch status {
        case .authorized, .limited: .allowed
        case .notDetermined: .undecided
        case .denied, .restricted: .refused
        @unknown default: .refused
        }
    }

    func photographs(during span: DateInterval) async -> [DayPhotograph] {
        // Never asks, and answers nothing where it may not read — the seam's
        // first promise, and what keeps a system alert out from in front of a
        // day that is being opened.
        guard access == .allowed else { return [] }

        let query = PHFetchOptions()
        // Half open at the end, so the first instant of the next day belongs
        // to the next day. Videos and live-photo pairings are left out: what
        // this offers goes into the Entry through the attachment pipeline,
        // which keeps the formats anything can open (``AttachmentFormat``).
        query.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
            PHAssetMediaType.image.rawValue,
            span.start as NSDate,
            span.end as NSDate
        )
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        var found: [DayPhotograph] = []
        PHAsset.fetchAssets(with: query).enumerateObjects { asset, _, _ in
            // Only ever nil for an asset the predicate above could not have
            // matched, but the identity of a photograph in a day is the moment
            // it was taken and there is nothing to offer without one.
            guard let takenAt = asset.creationDate else { return }
            found.append(
                DayPhotograph(
                    id: asset.localIdentifier,
                    takenAt: takenAt,
                    // Read off the index beside the date, at no extra cost —
                    // and `nil` far more often than not: a screenshot, a
                    // picture saved from a message, a camera with location
                    // turned off. Which is a day that falls back on the live
                    // fix, never a day that fails.
                    position: asset.location.map {
                        Coordinate(
                            latitude: $0.coordinate.latitude,
                            longitude: $0.coordinate.longitude
                        )
                    }
                )
            )
        }
        return found
    }

    func thumbnail(of photograph: DayPhotograph) async -> Data? {
        guard let asset = Self.asset(photograph) else { return nil }

        let wanted = PHImageRequestOptions()
        wanted.deliveryMode = .opportunistic
        wanted.resizeMode = .fast
        // A thumbnail of a photograph that is only in iCloud is worth waiting
        // for — it is a hundredth of the photograph, and without it the panel
        // is a row of grey squares.
        wanted.isNetworkAccessAllowed = true

        // Encoded where PhotoKit hands it over, so that what travels back is
        // bytes: the seam is Core's and Core may not know what a `UIImage` is.
        // Cheap, which is what re-encoding a 120-point square is.
        return await Self.answered { finished in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: Self.thumbnailSize,
                contentMode: .aspectFill,
                options: wanted
            ) { image, _ in finished(image?.jpegData(compressionQuality: 0.8)) }
        }
    }

    func contents(of photograph: DayPhotograph) async -> Data? {
        guard let asset = Self.asset(photograph) else { return nil }

        let wanted = PHImageRequestOptions()
        // The photograph itself and not a preview of it: this is the one that
        // goes into somebody's folder for good.
        wanted.deliveryMode = .highQualityFormat
        wanted.version = .current
        wanted.isNetworkAccessAllowed = true

        return await Self.answered { finished in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: wanted
            ) { data, _, _, _ in finished(data) }
        }
    }

    /// The strip's square at the densest screen Aujour runs on — sharp there
    /// and everywhere below it, and nowhere near enough to be worth caching.
    ///
    /// In pixels, which is what PhotoKit means by a target size, and derived
    /// from the points the panel draws rather than guessed: a thumbnail
    /// fetched larger than the square it goes in is a decode and a downscale
    /// of somebody's whole photograph, once per square in the strip.
    private static let thumbnailSize = CGSize(
        width: PhotoSuggestionsPanel.square * 3,
        height: PhotoSuggestionsPanel.square * 3
    )

    private static func asset(_ photograph: DayPhotograph) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [photograph.id], options: nil).firstObject
    }

    /// One answer from an image request, however many times PhotoKit calls
    /// back.
    ///
    /// Opportunistic delivery answers twice — a blurred placeholder, then the
    /// real thing — and a continuation resumed twice is a crash. So the first
    /// answer is the answer, which for a thumbnail means the panel fills in
    /// fast and for the photograph itself means the only callback there was.
    private static func answered<Value: Sendable>(
        _ request: (@escaping @Sendable (Value?) -> Void) -> Void
    ) async -> Value? {
        let once = TheFirstAnswer<Value>()
        return await withCheckedContinuation { continuation in
            once.waitOn(continuation)
            request { answer in once.resume(with: answer) }
        }
    }
}

/// A continuation that is resumed once, whoever gets there first.
///
/// Unchecked because PhotoKit answers on a queue of its own choosing, which is
/// what the lock is for.
private final class TheFirstAnswer<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var answered = false

    func waitOn(_ continuation: CheckedContinuation<Value?, Never>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    func resume(with value: Value?) {
        lock.lock()
        let waiting = answered ? nil : continuation
        answered = true
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
    }
}
