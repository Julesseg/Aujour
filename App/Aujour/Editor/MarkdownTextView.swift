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
    /// How much of the top of this view the glass over the page takes: the
    /// date pill, and the row it sits in.
    ///
    /// Room the page holds clear above its own first line, and not a frame
    /// that stops where the glass begins. The pill is glass, and glass over a
    /// page that ended underneath it has nothing to refract — so the text view
    /// fills the screen, keeps this much of itself clear, and a day scrolled up
    /// passes behind the pill the way it is meant to.
    ///
    /// Room *inside the page* rather than an inset above it, which is the
    /// whole difference: an inset would rest the page below its own top, and
    /// what lives up there is the tucked control — which would then sit
    /// showing through the glass at rest, where nothing has reached for it.
    var roomForTheGlass: CGFloat = 0 {
        didSet {
            guard roomForTheGlass != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// The section, once there is one to show.
    private var header: UIHostingController<FrontmatterSection>?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        // Where the row above the keyboard is, is the keyboard's to say, and
        // how much room the page keeps below its words is the row's. Neither
        // of them moves this view, so neither of them would lay it out again
        // on its own.
        for moment in [
            UIResponder.keyboardDidShowNotification,
            UIResponder.keyboardDidChangeFrameNotification,
            UIResponder.keyboardDidHideNotification,
        ] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(setNeedsLayout), name: moment, object: nil
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownTextView is not loaded from a nib")
    }

    /// Whether the header is the tucked-away control rather than the section.
    private var isTucked = false

    /// Whether the tucked control has been pulled into view and left there.
    private var isRevealed = false

    /// The room around the text without the header: what the header's height
    /// is added to.
    var baseInset: UIEdgeInsets = .zero {
        didSet { setNeedsLayout() }
    }

    /// How tall the header came out last time it was measured.
    private var headerHeight: CGFloat = 0

    /// How much of the bottom of the page the row above the keyboard covers.
    ///
    /// Room the page keeps below its last line, and the mirror of the room it
    /// keeps above its first: the row is a pane over the words rather than a
    /// floor under them, so a day scrolled to its end would come to rest with
    /// its last line beneath the glass and nowhere further to go.
    ///
    /// Measured against the row where it actually is rather than read off a
    /// height: the row is as tall as the reader's text size makes it, it
    /// carries the home indicator's room when it is docked above a hardware
    /// keyboard, and on a layout where the page already stops above it there
    /// is nothing over the words and the answer is nought.
    private var roomForTheRowOverThePage: CGFloat {
        guard window != nil, let row = inputAccessoryView, row.window != nil else { return 0 }
        return Self.room(
            below: convert(bounds, to: nil),
            coveredBy: row.convert(row.bounds, to: nil)
        )
    }

    /// How far a pane over the page reaches up into what the page is showing.
    ///
    /// Two rectangles and no view, so that the one thing here that is a rule
    /// rather than a wiring can be asked without a keyboard on screen to ask
    /// it of.
    static func room(below page: CGRect, coveredBy pane: CGRect) -> CGFloat {
        max(0, page.maxY - pane.minY)
    }

    /// Whether the last layout was one with the control pulled into view, and
    /// `nil` where the page is to be laid out afresh rather than moved.
    ///
    /// The glass's room changes hands between the text and the scroll view on
    /// exactly that transition, and a hand-over that moved the words under a
    /// reader's finger would be the page jumping mid-pull. So the offset is
    /// corrected there and nowhere else: a page being opened, one put back to
    /// its top, and one whose room simply changed size — a notice arriving
    /// over it, the text turned up — have all of them nothing to correct.
    private var laidOutPulledIn: Bool?

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
            laidOutPulledIn = nil
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
        // Placed rather than moved: this is a page being opened, and the top
        // it opens at is its own.
        laidOutPulledIn = nil
        setNeedsLayout()
        if contentOffset.y < 0 { contentOffset.y = 0 }
    }

    /// A finger has let go of the page. Pulled far enough past the top, the
    /// tucked control is left in view.
    ///
    /// Far enough is the control's own height and not the room the pull opens,
    /// which is that and the glass's on top. A page pulled past its top is
    /// rubber-banding, and a finger buys less travel the further it goes: a
    /// threshold read off the whole room would ask for a drag most of the way
    /// down the screen. What is asked for is the ask, and what opens is the
    /// room — the way a refresh control opens.
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
            laysTheTopOut(inTheText: roomForTheGlass, aboveThePage: 0, pulledIn: false)
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

        // Where the header sits, and what the top of the page is made of
        // around it — the three placements of the two states a day is in.
        //
        // The section is the top of a day that has a block: under the glass's
        // room and over the first line, both of them inside the page, so that
        // the block scrolls up behind the pill like everything else.
        //
        // The tucked control sits above the page's own top, where the glass
        // has nothing of it to show either. Pulled into view, the room it
        // needs *and* the glass's are held above the page by the scroll view,
        // and the text hands the glass's back — so the control comes to rest
        // clear of the pill with the first line its own inset below it, and
        // not the glass's room twice over.
        let y: CGFloat
        let inTheText: CGFloat
        let aboveThePage: CGFloat
        switch (isTucked, isRevealed) {
        case (false, _):
            y = roomForTheGlass
            inTheText = roomForTheGlass + headerHeight
            aboveThePage = 0
        case (true, false):
            y = -headerHeight
            inTheText = roomForTheGlass
            aboveThePage = 0
        case (true, true):
            y = -headerHeight
            inTheText = 0
            aboveThePage = roomForTheGlass + headerHeight
        }

        let frame = CGRect(x: 0, y: y, width: width, height: headerHeight)
        if header.view.frame != frame { header.view.frame = frame }

        laysTheTopOut(inTheText: inTheText, aboveThePage: aboveThePage, pulledIn: isTucked && isRevealed)
    }

    /// Leaves this much room above the text inside the page, and this much
    /// above the page itself — without moving the page under anybody, since a
    /// reader with a finger on it is the only one who may.
    private func laysTheTopOut(inTheText: CGFloat, aboveThePage: CGFloat, pulledIn: Bool) {
        let handedOver = laidOutPulledIn != nil && laidOutPulledIn != pulledIn
        laidOutPulledIn = pulledIn

        // The room above the page is opened first and the room inside it
        // taken away second, and the order is not a nicety. A day of three
        // lines is shorter than the screen, so the only offset such a page
        // will hold is its own top: hand the glass's room over before there
        // is anywhere above the page to put it, and the offset that hand-over
        // needs is clamped away — which reads as a control that sprang back
        // rather than one that opened.
        if contentInset.top != aboveThePage {
            let offset = contentOffset
            contentInset.top = aboveThePage
            contentOffset = offset
        }

        var inset = baseInset
        inset.top += inTheText
        inset.bottom += roomForTheRowOverThePage
        if textContainerInset != inset {
            let moved = inset.top - textContainerInset.top
            textContainerInset = inset
            // The glass's room has just changed hands: the text moved inside
            // the page, so the page moves the same distance the other way and
            // nothing on screen moves at all.
            if handedOver { contentOffset.y += moved }
        }
    }
}
