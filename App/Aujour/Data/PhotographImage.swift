import ImageIO
import UIKit

nonisolated enum PhotographImage {
    static func decode(_ data: Data, maximumPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        return decode(source, maximumPixelSize: maximumPixelSize)
    }

    static func thumbnail(_ data: Data, squarePixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
        ), let dimensions = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = dimensions[kCGImagePropertyPixelWidth] as? Double,
              let height = dimensions[kCGImagePropertyPixelHeight] as? Double,
              min(width, height) > 0 else { return nil }
        let largest = Int((Double(squarePixelSize) * max(width, height) / min(width, height)).rounded(.up))
        return decode(source, maximumPixelSize: largest)?.jpegData(compressionQuality: 0.95)
    }

    private static func decode(_ source: CGImageSource, maximumPixelSize: Int) -> UIImage? {
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            ] as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: image)
    }
}
