import SwiftUI
import UIKit

/// The text view an Entry is written in, with room above its text for the
/// Frontmatter section.
///
/// The section is a SwiftUI view hosted *inside* the text view, above the
/// first line and scrolling with it, rather than a view pinned over the top
/// of the screen. A text view is a scroll view, and it is the only one on the
/// page: a day of three thousand words is laid out lazily by it, so nothing
/// can sit above the words without sitting inside it — and a section pinned
/// outside would take its height off every screenful of a long day, however
/// far down the reader had scrolled.
///
/// Two placements, for the two states a day is in (`CONTEXT.md`,
/// *Frontmatter*). A day with a block has the section over its first line,
/// and the text starts under it. A day without one has only the small control
/// that adds a first Property, tucked above the top: out of sight at rest,
/// pulled into view by scrolling up past the first line, and in the
/// accessibility tree the whole time.
///
/// Tucked away means above the content, where only a pull past the top
/// reaches — and it stays once pulled, the way a refresh control does: the
/// pull that reached it opens room for it above the first line, and
/// scrolling back down closes that room again. The room is never open at
/// rest, deliberately. A scroll view whose top inset is open re-clamps its
/// offset to that inset whenever its frame or its insets move — a keyboard
/// rising is enough — and the page would keep landing with the control in
/// view and the first line a control's height lower than everything aimed at
/// it expects.
final class MarkdownTextView: UITextView {
    /// The section, once there is one to show.
    private var header: UIHostingController<FrontmatterSection>?

    /// Whether the header is the tucked-away control rather than the section.
    private var isTucked = false

    /// Whether the tucked control has been pulled into view and left there.
    private var isRevealed = false

    /// The room around the text without the header: what the header's height
    /// is added to.
    var baseInset: UIEdgeInsets = .zero {
        didSet {
            if header == nil { textContainerInset = baseInset }
            setNeedsLayout()
        }
    }

    /// How tall the header came out last time it was measured.
    private var headerHeight: CGFloat = 0

    /// Whether the header has to be measured again before it is placed —
    /// because what it shows changed, or the width it is laid out in did.
    private var needsHeaderMeasure = true

    private var measuredWidth: CGFloat = 0

    /// What the header was last measured for, so that a keystroke in the
    /// body — which rebuilds the section like everything else on the screen
    /// — does not lay the section out again for a height that cannot have
    /// moved.
    private var measuredFor: Int?

    /// Puts this section above the text, or moves the one that is there on
    /// to showing this.
    ///
    /// - Parameter tucked: whether it is the discreet control over a day with
    ///   no block, which is kept above the top rather than over the first
    ///   line.
    func shows(_ section: FrontmatterSection, tucked: Bool) {
        if let header {
            header.rootView = section
        } else {
            let header = UIHostingController(rootView: section)
            header.view.backgroundColor = .clear
            // Inside a scroll view's content, not under a bar: the window's
            // safe area is nothing to this view, and left to SwiftUI it would
            // be padded in over the first row and counted in the height.
            header.safeAreaRegions = []
            // Sized by what it holds, so that a section that gained a row asks
            // to be laid out again.
            header.sizingOptions = [.intrinsicContentSize]
            addSubview(header.view)
            self.header = header
            adoptHeader()
        }
        if isTucked != tucked {
            isTucked = tucked
            // A day that just lost its last Property tucks the control away;
            // a day that just gained its first shows the section from the
            // top. Both are the top of the page, which is offset nought.
            isRevealed = false
            contentOffset.y = 0
        }
        guard measuredFor != section.layoutFingerprint else { return }
        measuredFor = section.layoutFingerprint
        needsHeaderMeasure = true
        setNeedsLayout()
    }

    /// Takes the section down, and out of the screen it was a child of.
    func removesTheSection() {
        guard let header else { return }
        header.willMove(toParent: nil)
        header.view.removeFromSuperview()
        header.removeFromParent()
        self.header = nil
    }

    /// Puts the tucked control back above the top — for a page that has just
    /// been given its text, which is a page opened afresh.
    ///
    /// Asked for rather than done on every layout, because the control is
    /// meant to be found: a reader who pulled it into view keeps it there
    /// until they scroll on.
    func tucksTheControlAway() {
        guard isTucked, isRevealed else { return }
        isRevealed = false
        setNeedsLayout()
        if contentOffset.y < 0 { contentOffset.y = 0 }
    }

    /// A finger has let go of the page. Pulled far enough past the top, the
    /// tucked control is left in view.
    func draggingEnded() {
        guard isTucked, !isRevealed, headerHeight > 0,
            contentOffset.y < -max(headerHeight * 0.6, 24)
        else { return }
        isRevealed = true
        setNeedsLayout()
    }

    /// The page moved. Scrolled back down past its first line, the room the
    /// revealed control had is closed again — from a position it is not in,
    /// so nothing on screen jumps.
    func scrolled() {
        guard isTucked, isRevealed, contentOffset.y >= 0 else { return }
        isRevealed = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeHeader()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        adoptHeader()
    }

    /// Makes the header a child of the screen it is on, so that what it
    /// presents — a menu asking a kind, a date picker's popover — has a
    /// view controller to be presented from.
    private func adoptHeader() {
        guard let header, header.parent == nil, window != nil else { return }
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController {
                controller.addChild(header)
                header.didMove(toParent: controller)
                return
            }
            responder = current.next
        }
    }

    /// Measures the header at this width when something about it changed,
    /// and puts it where its state says: over the first line, or above the
    /// top.
    private func placeHeader() {
        guard let header else {
            if textContainerInset != baseInset { textContainerInset = baseInset }
            return
        }
        let width = bounds.width
        guard width > 0 else { return }

        if needsHeaderMeasure || width != measuredWidth {
            needsHeaderMeasure = false
            measuredWidth = width
            headerHeight = ceil(
                header.sizeThatFits(in: CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
                    .height
            )
        }

        let frame = CGRect(x: 0, y: isTucked ? -headerHeight : 0, width: width, height: headerHeight)
        if header.view.frame != frame { header.view.frame = frame }

        var inset = baseInset
        if !isTucked { inset.top += headerHeight }
        if textContainerInset != inset { textContainerInset = inset }

        // Tucked and pulled into view, the control has room above the
        // content to rest in; tucked and not, it has none, and sits above
        // the top where only a pull reaches.
        let above = isTucked && isRevealed ? headerHeight : 0
        if contentInset.top != above {
            let offset = contentOffset
            contentInset.top = above
            contentOffset = offset
        }
    }
}
