import UniformTypeIdentifiers
import Photos
import Testing
import UIKit

@testable import Aujour

struct PhotoKitLibraryTests {
    @Test("a temporary low-quality image is replaced by the requested thumbnail")
    func waitsForTheSharpImage() async throws {
        let placeholder = image(width: 12)
        let sharp = image(width: 450)
        let data = await PhotoKitLibrary.imageData(
            targetSize: CGSize(width: 450, height: 450), contentMode: .aspectFill
        ) { _, _, _, result in
            result(placeholder, [PHImageResultIsDegradedKey: true])
            result(sharp, [PHImageResultIsDegradedKey: false])
        }
        let decoded = try #require(data.flatMap(UIImage.init(data:)))
        #expect(decoded.cgImage?.width == 450)
    }

    @Test("failed and cancelled requests finish even when marked degraded", arguments: [true, false])
    func failedRequest(cancelled: Bool) async {
        let data = await PhotoKitLibrary.imageData(
            targetSize: CGSize(width: 450, height: 450), contentMode: .aspectFill
        ) { _, _, _, result in
            var info: [AnyHashable: Any] = [PHImageResultIsDegradedKey: true]
            if cancelled {
                info[PHImageCancelledKey] = true
            } else {
                info[PHImageErrorKey] = NSError(domain: "PhotoKitLibraryTests", code: 1)
            }
            result(nil, info)
        }
        #expect(data == nil)
    }

    @Test("requests a sharp image at the grid's pixel size")
    func requestQuality() async {
        let data = await PhotoKitLibrary.imageData(
            targetSize: CGSize(width: 450, height: 450), contentMode: .aspectFill
        ) { size, mode, options, result in
            #expect(size == CGSize(width: 450, height: 450))
            #expect(mode == .aspectFill)
            #expect(options.deliveryMode == .highQualityFormat)
            #expect(options.resizeMode == .exact)
            #expect(options.isNetworkAccessAllowed)
            result(image(width: 450), nil)
            result(nil, nil)
        }
        #expect(data != nil)
    }

    @Test("an unavailable PhotoKit thumbnail falls back to a sharp downsample of the photo")
    func recoversMissingThumbnail() async throws {
        let original = try #require(image(width: 900).jpegData(compressionQuality: 1))
        let data = await PhotoKitLibrary.thumbnailData(
            loadingThumbnail: { nil }, loadingContents: { original }
        )
        let decoded = try #require(data.flatMap(UIImage.init(data:)))
        #expect(decoded.cgImage?.width == 450)
        #expect(decoded.cgImage?.height == 450)
    }

    @Test("a successful thumbnail never fetches the full photo")
    func thumbnailDoesNotDownloadOriginal() async throws {
        let thumbnail = try #require(image(width: 450).jpegData(compressionQuality: 1))
        let data = await PhotoKitLibrary.thumbnailData(
            loadingThumbnail: { thumbnail },
            loadingContents: {
                Issue.record("Downloaded an original despite having a thumbnail")
                return nil
            }
        )
        #expect(data == thumbnail)
    }

    @Test("fallback thumbnails keep enough pixels to fill a square and honor orientation")
    func rectangularFallback() throws {
        let original = try #require(UITestingJournal.photograph(as: .jpeg, orientation: 6))
        let data = try #require(PhotographImage.thumbnail(original, squarePixelSize: 15))
        let decoded = try #require(UIImage(data: data)?.cgImage)
        #expect(decoded.width == 15)
        #expect(decoded.height == 20)
    }

    private func image(width: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: width), format: format
        ).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: width))
        }
    }
}
