import AujourCore
import ImageIO
import SwiftUI

struct PhotoSuggestionPreview: View {
    let photograph: DayPhotograph
    let suggestions: PhotoSuggestions

    @State private var image: UIImage?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Photo taken at \(photograph.takenAt.formatted(date: .omitted, time: .shortened))")
                    .accessibilityIdentifier("photoSuggestionPreviewImage")
            } else if unavailable {
                ContentUnavailableView("Photo unavailable", systemImage: "photo")
            } else {
                ProgressView("Loading photo…")
            }
        }
        .frame(width: 320, height: 420)
        .background { SurfaceFill(.sheet) }
        .task(id: photograph.id) {
            image = nil
            unavailable = false
            if let data = await suggestions.contents(of: photograph) {
                image = await Task.detached {
                    Self.image(from: data)
                }.value
            }
            guard !Task.isCancelled else { return }
            unavailable = image == nil
        }
    }

    private nonisolated static func image(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
        ), let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
            ] as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: image)
    }
}
