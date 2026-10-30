import UIKit

enum EntrySurface {
    static let cornerRadius: CGFloat = 32
    static let margin: CGFloat = 16
    static let padding: CGFloat = 22
    static let gap: CGFloat = 16
    static let minimumHeight: CGFloat = 480

    static func textInset(lineFragmentPadding: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(
            top: gap + padding,
            left: margin + padding - lineFragmentPadding,
            bottom: padding + margin,
            right: margin + padding - lineFragmentPadding
        )
    }
}
