import AujourCore
import UIKit

/// The formatting bar above the keyboard: headings, bold and italic, lists,
/// checkboxes, indenting, and a photograph.
///
/// Markdown is written with punctuation, and punctuation is where a phone
/// keyboard is slowest — `#`, `*` and `[` are two taps and a shifted layout
/// away each. So the marks a journal is actually written with are one tap on
/// glass, and the row is above the keyboard where the thumbs already are.
///
/// It holds no rules. Which characters a control writes, and where that leaves
/// the cursor, is ``AujourCore/MarkdownFormatting``'s — unit-tested on Linux
/// against the text it rewrites — and this is the buttons, their symbols, and
/// the accessibility labels that are the only way to press one without seeing
/// it. A control is a shortcut for markdown the user could type by hand, and
/// the Entry is a plain markdown file before and after (ADR 0001).
///
/// ## Coming and going with the keyboard
///
/// It is the text view's `inputAccessoryView`, which is what makes that true
/// without anybody arranging it: the row is on screen exactly while the Entry
/// is being written in, on an iPhone, on an iPad, over a floating keyboard and
/// docked above a hardware one. A day nobody is writing in has no keyboard and
/// no row — which is the same rule live preview draws by, and leaves a day
/// being read as a document with nothing over it.
final class MarkdownAccessoryRow: UIInputView {
    /// What a control does when it is tapped. The row knows the commands and
    /// nothing about the text they are for.
    private let format: (MarkdownFormatting) -> Void

    /// What inserting a photograph does — the picker, the file written into
    /// the Journal Root, the embed at the caret, all of it
    /// ``InsertedPhotographs``'s. Nothing, for a row over a text view with no
    /// Entry behind it: the control is there and is not offered, because a
    /// button that looks live and does nothing is worse than one that says it
    /// is not ready.
    private let insertPhoto: (() -> Void)?

    init(insertPhoto: (() -> Void)? = nil, format: @escaping (MarkdownFormatting) -> Void) {
        self.insertPhoto = insertPhoto
        self.format = format
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: MarkdownAccessoryRow.rowHeight),
            inputViewStyle: .keyboard
        )

        // The height is this view's own to say, and it says it through
        // `intrinsicContentSize` — which is what a flexible height leaves room
        // for, and what an accessory view is measured by.
        autoresizingMask = .flexibleHeight
        allowsSelfSizing = true
        accessibilityIdentifier = "markdownAccessoryRow"

        layOutControls()

        // Dynamic Type moves the symbols, and the row has to be as tall as
        // whatever they came out.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (row: Self, _) in row.invalidateIntrinsicContentSize()
        }
    }

    /// Never happens: an accessory row is made with the editor it sits over,
    /// and nothing archives one.
    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - How tall it is

    /// A thumb's worth, grown with the text size — a row whose symbols are
    /// larger than the room they are in is a row somebody is aiming at from
    /// memory. Capped, because past a point it is the keyboard that has to
    /// stay on screen.
    private static var rowHeight: CGFloat {
        min(UIFontMetrics(forTextStyle: .body).scaledValue(for: 44), 64)
    }

    override var intrinsicContentSize: CGSize {
        // Plus whatever the device keeps for itself below: docked above a
        // hardware keyboard on an iPad, the row is the last thing before the
        // home indicator.
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: MarkdownAccessoryRow.rowHeight + safeAreaInsets.bottom
        )
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
    }

    // MARK: - The controls

    private func layOutControls() {
        let controls = UIStackView(arrangedSubviews: buttons())
        controls.axis = .horizontal
        controls.spacing = 2
        controls.translatesAutoresizingMaskIntoConstraints = false

        // Scrolled, because there are nine controls and a phone can be narrow
        // and its text large: a row that ran off the edge would be a row whose
        // last controls do not exist.
        let scroller = UIScrollView()
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.showsHorizontalScrollIndicator = false
        scroller.addSubview(controls)
        addSubview(scroller)

        NSLayoutConstraint.activate([
            scroller.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scroller.topAnchor.constraint(equalTo: topAnchor),
            scroller.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),

            controls.leadingAnchor.constraint(
                equalTo: scroller.contentLayoutGuide.leadingAnchor, constant: 8
            ),
            controls.trailingAnchor.constraint(
                equalTo: scroller.contentLayoutGuide.trailingAnchor, constant: -8
            ),
            controls.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            controls.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            controls.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),
        ])
    }

    /// The row, left to right: what a line is, then what a word is, then the
    /// lists, then where the line sits, then the one thing that is not
    /// punctuation at all.
    private func buttons() -> [UIButton] {
        [
            headings(),
            control(.strong, "bold", "Bold", "formatBold"),
            control(.emphasis, "italic", "Italic", "formatItalic"),
            control(.bulletList, "list.bullet", "Bullet list", "formatBulletList"),
            control(.numberedList, "list.number", "Numbered list", "formatNumberedList"),
            control(.taskList, "checklist", "Checkbox", "formatTaskList"),
            control(.outdent, "decrease.indent", "Outdent", "formatOutdent"),
            control(.indent, "increase.indent", "Indent", "formatIndent"),
            photograph(),
        ]
    }

    private func control(
        _ command: MarkdownFormatting,
        _ symbol: String,
        _ label: String,
        _ identifier: String
    ) -> UIButton {
        button(symbol, label, identifier) { [weak self] in self?.format(command) }
    }

    /// One button for the six levels markdown has, because six buttons would
    /// be a row of nothing else — and the three a journal is written in are
    /// the ones offered.
    private func headings() -> UIButton {
        let button = button("textformat.size", "Heading", "formatHeading", tapped: nil)
        button.menu = UIMenu(
            children: (1...3).map { level in
                UIAction(title: "Heading \(level)") { [weak self] _ in
                    self?.format(.heading(level: level))
                }
            }
        )
        // One tap opens it: nobody is going to press and hold above a keyboard.
        button.showsMenuAsPrimaryAction = true
        return button
    }

    /// The way to a photograph, which is the one control here that does not
    /// write punctuation.
    ///
    /// Only the affordance, in the row where somebody writing would look for
    /// it. What it sets going — the picker, the file copied into the Journal
    /// Root under the Attachment Path Template, the embed written at the caret
    /// — belongs to whoever handed the row a way to do it, exactly as what a
    /// formatting control writes belongs to Core.
    private func photograph() -> UIButton {
        let button = button("photo.badge.plus", "Insert photo", "insertPhoto") {
            [weak self] in self?.insertPhoto?()
        }
        button.isEnabled = insertPhoto != nil
        return button
    }

    private func button(
        _ symbol: String,
        _ label: String,
        _ identifier: String,
        tapped: (() -> Void)?
    ) -> UIButton {
        let button = UIButton(
            type: .system,
            primaryAction: tapped.map { tapped in
                UIAction(image: UIImage(systemName: symbol)) { _ in tapped() }
            }
        )
        // Set again for the menu button, which has no action to carry it.
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(textStyle: .body), forImageIn: .normal
        )
        // A thumb's worth of button, whatever the symbol inside it measures.
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        // What a UI test presses it by, and — with a symbol for a label and no
        // words anywhere — the only thing VoiceOver has to say about it.
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        return button
    }
}
