import SwiftUI
import Testing
import UIKit

@testable import Aujour

@MainActor
struct PhotoSuggestionButtonTests {
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
