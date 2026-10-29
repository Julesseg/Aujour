import AujourCore
import SwiftUI
import Testing
import UIKit

@testable import Aujour

@MainActor
struct PhotoSuggestionButtonTests {
    @Test("a preview starts at its final proportions on the first and repeated opening",
           arguments: [CGSize(width: 210, height: 420), CGSize(width: 320, height: 240),
                       CGSize(width: 315, height: 420)])
    func initialPreviewSize(size: CGSize) {
        let photo = PhotoSuggestionButton(
            thumbnail: nil, isLoading: false, identifier: "photo", photographID: "photo",
            label: "Photo", add: {}, showPreview: {}
        ) { Color.orange.frame(width: size.width, height: size.height) }
        for _ in 0..<2 {
            let controller = photo.previewController()
            #expect(controller.preferredContentSize == size)
            controller.loadViewIfNeeded()
            controller.view.layoutIfNeeded()
            #expect(controller.preferredContentSize == size)
            #expect(controller.view.bounds.size == size)
        }
    }

    @Test("a loading photo already has its final preview window",
           arguments: [CGSize(width: 210, height: 420), CGSize(width: 320, height: 240),
                       CGSize(width: 315, height: 420)])
    func loadingPreviewSize(size: CGSize) {
        let photograph = DayPhotograph(
            id: "photo", takenAt: .distantPast, aspectRatio: Double(size.width / size.height)
        )
        let suggestions = PhotoSuggestions()
        let photo = PhotoSuggestionButton(
            thumbnail: nil, isLoading: false, identifier: "photo", photographID: "photo",
            label: "Photo", add: {}, showPreview: {}
        ) { PhotoSuggestionPreview(photograph: photograph, suggestions: suggestions) }
        for _ in 0..<2 {
            let controller = photo.previewController()
            #expect(controller.preferredContentSize == size)
            #expect(controller.view.bounds.size == size)
        }
    }

    @Test("a menu closing before finger-up does not turn a hold into insertion")
    func endingAMenuDuringAHold() throws {
        var additions = 0
        let photo = PhotoSuggestionButton(
            thumbnail: nil, isLoading: false, identifier: "photo", photographID: "photo",
            label: "Photo", add: { additions += 1 }, showPreview: {}
        ) { Color.clear }
        let coordinator = photo.makeCoordinator()
        let button = PhotographButton(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        button.add = { additions += 1 }
        let interaction = UIContextMenuInteraction(delegate: coordinator)
        button.addInteraction(interaction)
        button.sendActions(for: .touchDown)
        let configuration = try #require(coordinator.contextMenuInteraction(
            interaction, configurationForMenuAtLocation: CGPoint(x: 50, y: 50)
        ))
        let delegate: any UIContextMenuInteractionDelegate = coordinator
        delegate.contextMenuInteraction?(interaction, willEndFor: configuration, animator: nil)
        button.sendActions(for: .touchUpInside)
        #expect(additions == 0)
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        #expect(additions == 1)
        #expect(button.accessibilityActivate())
        #expect(additions == 2)
    }
}
