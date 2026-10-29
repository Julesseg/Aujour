import Foundation
import Testing

@testable import AujourCore

struct DayPhotographTests {
    @Test("image proportions are available before loading photo bytes", arguments: [0.5, 4.0 / 3])
    func imageProportions(ratio: Double) {
        let photo = DayPhotograph(id: "photo", takenAt: .distantPast, aspectRatio: ratio)
        #expect(photo.aspectRatio == ratio)
    }

    @Test("missing or invalid dimensions leave proportions unknown",
           arguments: [nil, 0, -1, Double.infinity, -Double.infinity, Double.nan] as [Double?])
    func unknownProportions(ratio: Double?) {
        let photo = DayPhotograph(id: "photo", takenAt: .distantPast, aspectRatio: ratio)
        #expect(photo.aspectRatio == nil)
    }
}
