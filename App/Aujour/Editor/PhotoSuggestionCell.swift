import SwiftUI
import UIKit

// A separate hosting tree keeps List from sharing a thumbnail's menu with its row.
struct PhotoSuggestionCell<Content: View>: UIViewControllerRepresentable {
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: hostedContent)
        controller.view.backgroundColor = .clear
        controller.safeAreaRegions = []
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<AnyView>, context: Context) {
        controller.rootView = hostedContent
        controller.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: UIHostingController<AnyView>,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return CGSize(width: width, height: width)
    }

    private var hostedContent: AnyView {
        AnyView(
            content
                .environment(\.accent, accent)
                .environment(\.colorScheme, colorScheme)
                .disabled(!isEnabled)
        )
    }
}
