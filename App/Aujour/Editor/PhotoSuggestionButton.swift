import AujourCore
import SwiftUI
import UIKit

struct PhotoSuggestionButton<Preview: View>: UIViewRepresentable {
    let thumbnail: UIImage?
    let isLoading: Bool
    let identifier: String
    let photographID: String
    let label: String
    let add: () -> Void
    let showPreview: () -> Void
    @ViewBuilder let preview: () -> Preview

    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PhotographButton {
        let button = PhotographButton(frame: .zero)
        button.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        return button
    }

    func updateUIView(_ button: PhotographButton, context: Context) {
        button.thumbnail.image = thumbnail
        if isLoading { button.loading.startAnimating() } else { button.loading.stopAnimating() }
        button.setImage(thumbnail == nil && !isLoading ? UIImage(systemName: "photo.badge.exclamationmark") : nil,
                        for: .normal)
        button.accessibilityValue = thumbnail == nil ? (isLoading ? "Loading photo" : "Photo unavailable") : nil
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        context.coordinator.parent = self
        button.isEnabled = isEnabled
        button.add = add
        button.showPreview = showPreview
    }

    private func previewController() -> UIViewController {
        let controller = UIHostingController(rootView: preview()
            .environment(\.accent, accent)
            .environment(\.colorScheme, colorScheme))
        controller.preferredContentSize = CGSize(width: 320, height: 420)
        controller.view.backgroundColor = .clear
        controller.safeAreaRegions = []
        controller.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return controller
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: PhotographButton, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return CGSize(width: width, height: width)
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var parent: PhotoSuggestionButton

        init(_ parent: PhotoSuggestionButton) { self.parent = parent }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard parent.isEnabled, let button = interaction.view as? PhotographButton else { return nil }
            button.isShowingPreview = true
            button.cancelTracking(with: nil)
            let photo = parent
            return UIContextMenuConfiguration(
                identifier: photo.photographID as NSString,
                previewProvider: { photo.previewController() },
                actionProvider: { _ in
                    UIMenu(children: [
                        UIAction(title: "Add to document", image: UIImage(systemName: "plus")) { _ in
                            photo.add()
                        }
                    ])
                }
            )
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willEndFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            guard let button = interaction.view as? PhotographButton else { return }
            if let animator {
                animator.addCompletion { [weak button] in button?.isShowingPreview = false }
            } else {
                button.isShowingPreview = false
            }
        }
    }
}

final class PhotographButton: UIButton {
    let thumbnail = UIImageView()
    let loading = UIActivityIndicatorView(style: .medium)
    var isShowingPreview = false
    var add: (() -> Void)?
    var showPreview: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .quaternarySystemFill
        layer.cornerRadius = Rounding.control
        layer.cornerCurve = .continuous
        clipsToBounds = true
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.isUserInteractionEnabled = false
        thumbnail.frame = bounds
        thumbnail.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(thumbnail)
        addSubview(loading)
        addAction(UIAction { [weak self] _ in
            guard let self, !isShowingPreview else { return }
            add?()
        }, for: .touchUpInside)
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Preview photo") { [weak self] _ in
                guard let self, isEnabled else { return false }
                showPreview?()
                return true
            }
        ]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        loading.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
