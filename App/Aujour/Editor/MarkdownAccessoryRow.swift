import AujourCore
import UIKit

/// The formatting bar above the keyboard: headings, bold and italic, lists,
/// checkboxes, indenting, and a photograph — and beside it, on a pane of its
/// own, the key to Suggestions.
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
///
/// ## Two panes, and which of them gives way
///
/// Two because they are two kinds of key: the strip rewrites the characters
/// under the cursor, and the one apart from it opens a sheet. A key put
/// outside the strip so that it is always in reach is not one to scroll out
/// of it — so where a phone is too narrow for both, the strip's keys scroll
/// under its own curve and the Suggestions key stays where it is.
///
/// Which is the whole of the arithmetic below. The strip is as wide as its
/// keys want to be, up to whatever is left once the second pane and the gap
/// between them have been taken out; past that the keys keep their floor and
/// run off the edge of the strip, where the scroller can reach them. On an
/// iPhone that is every width there is: nine keys at their floor and one key
/// beside them are wider than a phone, and only the largest fits all ten.
///
/// ## The pane they are drawn on
///
/// A pill of glass floating over the words, inset from the leading edge and
/// lifted off the keyboard, rather than a bar filling the width: the
/// identity's chrome sits *over* the paper and lets it show through, and a row
/// that reached both edges would read as part of the keyboard rather than as
/// something the app put there.
///
/// So the trailing inset is where the second pane sits. A phone has less room
/// than ten keys want and the panes take all of it; an iPad has more, the
/// formatting pane stops with its square
/// keys, and Suggestions sits at the far edge with paper between them. An
/// accessory view is as wide as the keyboard is, but neither pane becomes the
/// bar this row is not.
///
/// It is the platform's own glass, tinted to `Palette.glass`, rather than the
/// blur-and-paint the design file spells out in CSS. The mock is a web page
/// approximating a material the web does not have; on iOS 26 the material is
/// real, and `.62` of cream laid *over* a blur is simply cream — the pane
/// stops being a pane. Tinted, so it is still the identity's paper and not the
/// system's white. Glass lights and shades itself, so there is no ring and no
/// shadow here either; two rims that disagree look worse than one.
///
/// Reduce Transparency is the exception, and gets all of it back: no pane, so
/// `Palette.glassSolid` — the opaque colour glass averages to — with the ring
/// for an edge and `Elevation.floating` for the lift, because a cream capsule
/// on a cream page has nothing else to say it is in front.
///
/// The pill is a capsule rather than one of `Rounding`'s four corners, which
/// is that set's own instruction: a pill has no entry there because it is half
/// its own height, at every size the type scale can grow this row to.
///
/// ## What is behind it
///
/// Nothing, today. SwiftUI's keyboard avoidance shrinks the editor above this
/// row, so the words stop short of it and the pane is over blank paper — which
/// makes glass and paint identical on screen, and is why this file is not
/// worth a third opinion until that changes. The identity draws the row over
/// the text; when the editor stops moving out from under it, this is already
/// the thing that will show it.
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

    /// What the Suggestions key does — the sheet of the day's own material,
    /// which is the screen's to put up and not a text view's
    /// (``SuggestionsSheet``).
    ///
    /// `nil` on the same rule the photograph is: an insertion needs a caret,
    /// and a row over a text view with no Entry behind it has nothing to
    /// insert into. The key is there and is not offered.
    private let openSuggestions: (() -> Void)?

    /// The app's own colour, which is what a key fills with under a thumb.
    ///
    /// Handed in rather than read off `tintColor`, because an accessory view
    /// does not live in the app's window: the keyboard puts it in one of its
    /// own, where the app's tint does not reach and the answer would quietly
    /// be the system's blue. Settable, because the accent is a Device Setting
    /// and moving it has to reach a row that is already on screen.
    var accent: UIColor {
        didSet {
            guard accent != oldValue else { return }
            for control in controls { control.setNeedsUpdateConfiguration() }
        }
    }

    /// The pane the formatting keys sit on, which rounds and lifts itself.
    private let strip = GlassPill()

    /// The pane the Suggestions key sits on, alone — the same glass, and a
    /// pane of its own because it is the other kind of key.
    private let apart = GlassPill()

    /// Every key on either pane, in the order they sit in — held so that the
    /// accent moving can reach them without a walk back down the view tree.
    private var controls: [UIButton] = []

    /// The floor and the ceiling on how wide a key is, and the width a key
    /// takes when the room is nobody else's to want — held because all three
    /// move with the text size, the same way the row's own height does.
    private var narrowKeys: [NSLayoutConstraint] = []
    private var wideKeys: [NSLayoutConstraint] = []
    private var roomyKeys: [NSLayoutConstraint] = []

    /// How wide the Suggestions key is, which is square and stays square: it
    /// is the one key nothing squeezes, since the strip is what gives way.
    private var keyApart: NSLayoutConstraint?

    init(
        accent: UIColor,
        insertPhoto: (() -> Void)? = nil,
        openSuggestions: (() -> Void)? = nil,
        format: @escaping (MarkdownFormatting) -> Void
    ) {
        self.accent = accent
        self.insertPhoto = insertPhoto
        self.openSuggestions = openSuggestions
        self.format = format
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: MarkdownAccessoryRow.rowHeight),
            inputViewStyle: .default
        )

        // The height is this view's own to say, and it says it through
        // `intrinsicContentSize` — which is what a flexible height leaves room
        // for, and what an accessory view is measured by.
        autoresizingMask = .flexibleHeight
        allowsSelfSizing = true
        accessibilityIdentifier = "markdownAccessoryRow"

        layOutControls()
        drawTheGlass()

        // Dynamic Type moves the symbols, and the row has to be as tall as
        // whatever they came out.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (row: Self, _) in
            row.sizeTheKeys()
            row.invalidateIntrinsicContentSize()
        }
        // The ring is a `CGColor` on a layer, which is the one kind of colour
        // in UIKit that does not turn with the appearance by itself.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (row: Self, _) in row.drawTheGlass()
        }
        // And a reader who turns translucency off with the keyboard already up.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(drawTheGlass),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
    }

    /// Never happens: an accessory row is made with the editor it sits over,
    /// and nothing archives one.
    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - How tall it is

    /// A thumb's worth of key, grown with the text size — a key whose symbol
    /// is larger than the room it is in is a key somebody is aiming at from
    /// memory. Capped, because past a point it is the keyboard that has to
    /// stay on screen.
    private static var keyHeight: CGFloat {
        min(UIFontMetrics(forTextStyle: .body).scaledValue(for: 44), 64)
    }

    /// The gap above and below the keys — inside the pane, and again between
    /// the pane and the row's own edges.
    private static let padding = Spacing.tight

    /// How far the pane is held off the two screen edges, which is the inset
    /// the identity gives every piece of chrome that floats over the paper.
    private static let inset = Spacing.close

    /// The keys, the room around them, and the room around the pane.
    private static var rowHeight: CGFloat {
        keyHeight + padding * 4
    }

    override var intrinsicContentSize: CGSize {
        // The pill, the gap above and below it, and then whatever the device
        // keeps for itself: docked above a hardware keyboard on an iPad, the
        // row is the last thing before the home indicator.
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: MarkdownAccessoryRow.rowHeight + safeAreaInsets.bottom
        )
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
    }

    // MARK: - How wide a key is

    /// The narrowest a key is allowed to get.
    ///
    /// Nine keys and the room a tenth has taken beside them: at any width this
    /// file picks, nine of them are wider than a phone, and the ones that go
    /// over the edge are the last — the indents and the photograph. So the keys
    /// divide the strip between them instead, one width, whatever the room
    /// turns out to be, and this is the floor under that.
    ///
    /// It is less than the 44 a control standing on its own would take,
    /// because the height is what carries the target here: these are keys in
    /// a strip with keys either side, the way the keyboard's own are, and
    /// those are narrower than this. Under the floor the row scrolls, which
    /// after this is only ever a narrow phone with its text turned up.
    private static var narrowestKey: CGFloat {
        min(UIFontMetrics(forTextStyle: .body).scaledValue(for: 34), 48)
    }

    /// The widest, which is as wide as a key is tall: past square it stops
    /// reading as a key and starts reading as a button with a gap around it.
    /// An iPad has room for more than that, and the keys stop rather than
    /// take it.
    private static var widestKey: CGFloat { keyHeight }

    // MARK: - The glass

    /// The pane's tint, its ring, and whether it is a pane at all.
    ///
    /// Called again whenever one of the two things it reads moves: the
    /// appearance, because a ring is a `CGColor` and those do not turn by
    /// themselves, and Reduce Transparency, because a reader can ask for it
    /// while looking at this row.
    /// Both panes, because they are the same pane twice: the second one is a
    /// pane of glass for the same reason the first is, and a reader who turns
    /// translucency off is owed the same answer from each.
    @objc private func drawTheGlass() {
        for pill in [strip, apart] {
            guard !UIAccessibility.isReduceTransparencyEnabled else {
                // No pane, so the pill has to be a surface by itself: the
                // opaque colour glass averages to, and the ring and the lift
                // it would otherwise have got from the glass.
                pill.pane.effect = nil
                pill.pane.contentView.backgroundColor = Palette.glassSolid
                pill.pane.layer.borderWidth = 0.5
                pill.pane.layer.borderColor =
                    Palette.glassRing.resolvedColor(with: traitCollection).cgColor
                pill.lifted(true)
                continue
            }

            // The platform's own glass, tinted to the identity's paper rather
            // than painted over with it: a cream at `.62` laid on top of a
            // blur is a cream, and the pane stops being a pane.
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = Palette.glass
            pill.pane.effect = glass
            pill.pane.contentView.backgroundColor = .clear

            // Glass draws its own edge and its own shadow, and a second of
            // either is not twice as convincing — it is two rims that do not
            // agree.
            pill.pane.layer.borderWidth = 0
            pill.lifted(false)
        }
    }

    // MARK: - The controls

    private func layOutControls() {
        let formatting = buttons()
        let suggestions = suggestions()
        controls = formatting + [suggestions]

        // The formatting pane first and the Suggestions pane second, which is
        // the order a hand reaches them in and the order anything reading the
        // row comes to them in — VoiceOver, and a test walking the buttons.
        addSubview(strip)
        addSubview(apart)
        laysOut(formatting, onTheStrip: strip)
        lays(suggestions, onThePaneApart: apart)

        // Suggestions stays at the far edge: beside the formatting pane on a
        // phone, and across the spare paper from it on an iPad. It is still a
        // pill the width of one key, not glass stretched across that distance.
        //
        // Breakable, and it breaks once: an accessory view is built before
        // anything has told it how wide it is, and two panes and a gap inset
        // from both edges of nothing at all do not fit.
        let far = apart.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -Self.inset
        )
        far.priority = .required - 1

        NSLayoutConstraint.activate([
            // Inset from the leading edge and off the keyboard: panes over the
            // paper rather than a bar across the bottom of it.
            strip.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Self.inset
            ),
            // At least the screen-edge gap between the panes: on a phone that
            // is all the room there is, while an iPad leaves its spare paper
            // here instead of stretching either pill across it.
            apart.leadingAnchor.constraint(
                greaterThanOrEqualTo: strip.trailingAnchor, constant: Self.inset
            ),
            far,
        ] + [strip, apart].flatMap { pill in
            [
                pill.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
                pill.bottomAnchor.constraint(
                    equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Self.padding
                ),
            ]
        })
    }

    /// The formatting keys, on the pane they divide between them.
    ///
    /// Its width is the one thing on this row that gives way. The keys want to
    /// be square and the pane wants to be as wide as the keys; where that will
    /// not fit beside the second pane, the pane is cut to what is left and the
    /// keys keep their floor and run off the edge of it, which is what the
    /// scroller is here for.
    private func laysOut(_ keys: [UIButton], onTheStrip strip: GlassPill) {
        let row = UIStackView(arrangedSubviews: keys)
        row.axis = .horizontal
        row.spacing = Spacing.tight
        // One width between them, whatever that width comes out as: a key is
        // aimed at by where it sits in the row, and nine keys of nine widths
        // would be nine positions to learn instead of one strip.
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false

        // The two ends of that one width. What a key comes out at between
        // them is the pane's to say, and it says it through the constraint at
        // the bottom of this method.
        narrowKeys = keys.map {
            $0.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.narrowestKey)
        }
        wideKeys = keys.map {
            $0.widthAnchor.constraint(lessThanOrEqualToConstant: Self.widestKey)
        }
        // And what a key comes out at when nothing is pushing on it, which is
        // the ceiling: a phone squeezes the keys down off this, an iPad does
        // not squeeze at all, and on an iPad this is what the pane is as wide
        // as. Said out loud rather than left to the pane, because the pane
        // has stopped saying it — anywhere between the floor and the ceiling
        // would satisfy every other constraint here, and a width nine keys
        // are free to pick is a width they can pick differently.
        roomyKeys = keys.map { $0.widthAnchor.constraint(equalToConstant: Self.widestKey) }
        for key in roomyKeys { key.priority = .defaultHigh }
        NSLayoutConstraint.activate(narrowKeys + wideKeys + roomyKeys)

        // Scrolled, for the case the keys cannot divide their way out of: any
        // phone but the widest, where nine keys at their floor and the second
        // pane beside them are wider than the row. A strip that simply ran off
        // the edge would be a strip whose last controls do not exist.
        let scroller = UIScrollView()
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.showsHorizontalScrollIndicator = false
        // Named, because on a phone the last of these keys begins off the pane
        // and the only way to it is a swipe — which a UI test has to make, and
        // cannot make without something to make it on.
        scroller.accessibilityIdentifier = "formattingKeys"
        scroller.addSubview(row)

        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.pane.contentView.addSubview(scroller)

        // As wide as the keys are, which is what turns `fillEqually` into a
        // width: on an iPad the keys are as wide as a key gets and the pane is
        // only as wide as the nine of them.
        //
        // The lowest priority on the row, because it is what gives: on every
        // phone but the widest, nine keys at their floor and the Suggestions
        // key beside them want more than there is, and then the pane takes
        // what room is left over and the keys run off the edge of it.
        let fill = row.widthAnchor.constraint(
            equalTo: scroller.frameLayoutGuide.widthAnchor, constant: -Self.padding * 2
        )
        fill.priority = .required - 2

        NSLayoutConstraint.activate([
            // Never narrower than one key and the room around it, whatever the
            // row has been told its width is — which at the moment it is built
            // is nothing at all, and a pane cut to what is left of nothing is a
            // pane of negative width.
            strip.widthAnchor.constraint(
                greaterThanOrEqualToConstant: Self.narrowestKey + Self.padding * 2
            ),

            // Edge to edge across the pane, so the keys scroll under its own
            // curve rather than stopping short of it; held off the top and
            // bottom, so a pressed key's fill never reaches the rim.
            scroller.leadingAnchor.constraint(equalTo: strip.pane.contentView.leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: strip.pane.contentView.trailingAnchor),
            scroller.topAnchor.constraint(
                equalTo: strip.pane.contentView.topAnchor, constant: Self.padding
            ),
            scroller.bottomAnchor.constraint(
                equalTo: strip.pane.contentView.bottomAnchor, constant: -Self.padding
            ),

            // The same gap the keys have above and below them; the pane's own
            // curve is what holds the first key off its edge.
            row.leadingAnchor.constraint(
                equalTo: scroller.contentLayoutGuide.leadingAnchor, constant: Self.padding
            ),
            row.trailingAnchor.constraint(
                equalTo: scroller.contentLayoutGuide.trailingAnchor, constant: -Self.padding
            ),
            row.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),

            fill,
        ])
    }

    /// The Suggestions key, on the pane it has to itself.
    ///
    /// Square and pinned there, with no scroller and nothing to divide: this is
    /// the key the strip gives way for, and a pane the width of one key is a
    /// pane every phone has room for.
    private func lays(_ key: UIButton, onThePaneApart apart: GlassPill) {
        key.translatesAutoresizingMaskIntoConstraints = false
        apart.translatesAutoresizingMaskIntoConstraints = false
        apart.pane.contentView.addSubview(key)

        let square = key.widthAnchor.constraint(equalToConstant: Self.widestKey)
        keyApart = square

        NSLayoutConstraint.activate([
            square,
            // The same room around it the strip's keys have around theirs, so
            // that two panes of one height come out of one arithmetic.
            key.leadingAnchor.constraint(
                equalTo: apart.pane.contentView.leadingAnchor, constant: Self.padding
            ),
            key.trailingAnchor.constraint(
                equalTo: apart.pane.contentView.trailingAnchor, constant: -Self.padding
            ),
            key.topAnchor.constraint(
                equalTo: apart.pane.contentView.topAnchor, constant: Self.padding
            ),
            key.bottomAnchor.constraint(
                equalTo: apart.pane.contentView.bottomAnchor, constant: -Self.padding
            ),
        ])
    }

    /// Moves the two ends of a key's width to the text size the reader has
    /// just changed to, the way the row's height moves with it.
    private func sizeTheKeys() {
        for key in narrowKeys { key.constant = Self.narrowestKey }
        for key in wideKeys { key.constant = Self.widestKey }
        for key in roomyKeys { key.constant = Self.widestKey }
        keyApart?.constant = Self.widestKey
    }

    /// The strip, left to right: what a line is, then what a word is, then the
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
    ///
    /// Spelled `#`, which is what a heading *is* — the same character the
    /// control writes, and the same reading as the `B` and the `I` beside it.
    /// The system's `textformat.size` is the glyph for how big text is, and
    /// how big the Entry's text is is a writing preference that belongs on
    /// the Appearance screen rather than a control above the keyboard: this
    /// row writes marks into the file, and nothing on it changes how the file
    /// is displayed.
    private func headings() -> UIButton {
        let button = button("number", "Heading", "formatHeading", tapped: nil)
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

    /// The key to Suggestions, which is the whole of the second pane.
    ///
    /// A lightbulb, because what it opens is an offer rather than a command:
    /// the day's own photographs, meetings and list, waiting to be written in.
    /// Spelled in a word as well as a symbol, like every other key here — a
    /// mark on glass is nothing a screen reader can read out.
    ///
    /// Only the affordance. What is on the sheet, and what a tap on it writes,
    /// is ``SuggestionsSheet``'s and Core's; a key above a keyboard cannot put
    /// up a sheet, and does not try.
    private func suggestions() -> UIButton {
        let button = button("lightbulb", "Suggestions", "openSuggestions") {
            [weak self] in self?.openSuggestions?()
        }
        button.isEnabled = openSuggestions != nil
        return button
    }

    /// One key: a symbol in ink, and the accent under it while a thumb is
    /// down.
    ///
    /// The pressed state is the whole reason these are configured rather than
    /// drawn: a key on glass has nothing behind it to darken, so UIKit's own
    /// highlight — the image fading out — reads as the row going wrong rather
    /// than as a key going down. The identity fills the key instead and turns
    /// the mark to `Palette.onAccent`, which is the one place in the app a
    /// mark is written on the accent rather than in it.
    /// What a key is drawn in, given what state it is in.
    ///
    /// A plain function of the three things it depends on, and separate from
    /// the button so that it can be asked. The alternative is a test that sets
    /// `isHighlighted` on a button in no window and hopes UIKit agrees a
    /// thumb is down, which is a test of UIKit rather than of the identity.
    static func colours(accent: UIColor, enabled: Bool, pressed: Bool) -> (
        fill: UIColor, mark: UIColor
    ) {
        switch (enabled, pressed) {
        // Configuring a button takes away the dimming `type: .system` did for
        // free, so the one control that can be unavailable has to say so here
        // or stop saying it at all. `inkFaint` is the marker step, which is
        // what a symbol is.
        case (false, _): (.clear, Palette.inkFaint)
        case (true, true): (accent, Palette.onAccent)
        case (true, false): (.clear, Palette.ink)
        }
    }

    private func button(
        _ symbol: String,
        _ label: String,
        _ identifier: String,
        tapped: (() -> Void)?
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        // Drawn at the size of a footnote rather than of the prose. A mark on
        // a key is a label for the key, not a word in the Entry: at body size
        // it filled its key corner to corner, which reads as a symbol somebody
        // forgot to leave room around. Still a text style and not a number, so
        // it is a reader's own text size the mark grows with.
        configuration.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(textStyle: .footnote)
        configuration.background.cornerRadius = Rounding.control
        // A configured button pads its own image by default, which would set
        // the key's width before the constraint below ever got a say — and
        // nine keys padded twice over do not fit the pane.
        configuration.contentInsets = .zero

        let button = UIButton(
            configuration: configuration,
            primaryAction: tapped.map { tapped in UIAction { _ in tapped() } }
        )
        button.configurationUpdateHandler = { [weak self] key in
            guard let self else { return }
            let drawn = Self.colours(
                accent: accent, enabled: key.isEnabled, pressed: key.isHighlighted
            )
            key.configuration?.background.backgroundColor = drawn.fill
            key.configuration?.baseForegroundColor = drawn.mark
        }
        // What a UI test presses it by, and — with a symbol for a label and no
        // words anywhere — the only thing VoiceOver has to say about it.
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        return button
    }
}

/// The pane the keys sit on: glass, a capsule, and the shadows that lift it.
///
/// Two views and not one, because a pane has to clip its blur to its own
/// corners and a view that clips cannot cast anything past them — so the
/// outer one casts and the inner one clips.
///
/// It shapes itself. A capsule is half of however tall the view came out, and
/// the shadows are cast in that same outline, so both are answers only a
/// laid-out view has: the row above cannot give them, because when the row
/// lays out its own subviews this one has not laid out its own yet.
///
/// The capsule is asked for as a *configuration* rather than written onto the
/// layer, because the pane is glass and glass gets borrowed. Tapping the
/// heading key morphs this pill into the menu of levels and back again, and
/// through that animation the shape is UIKit's to interpolate: a radius set by
/// hand in `layoutSubviews` is a number UIKit has no reason to consult, so the
/// pane came back from the morph square and stayed square until the next thing
/// on screen happened to lay it out again. `.capsule()` is the same shape said
/// where the animation can read it.
private final class GlassPill: UIView {
    let pane = UIVisualEffectView()
    private var shadows: [CALayer] = []

    init() {
        super.init(frame: .zero)

        pane.clipsToBounds = true
        // Half of however tall the pill came out, at every text size — and
        // half of whatever it is *mid-morph*, which is the part a constant
        // could not have said.
        pane.cornerConfiguration = .capsule()
        // Circular rather than continuous: at half its own height the corner
        // *is* a semicircle, and the shadow underneath is cast with the same
        // arc — two curves that disagreed by a point would show as a rim.
        pane.layer.cornerCurve = .circular
        pane.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pane)

        shadows = Elevation.floating.castOn(self)

        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: trailingAnchor),
            pane.topAnchor.constraint(equalTo: topAnchor),
            pane.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Never happens: the row builds one and nothing archives it.
    required init?(coder: NSCoder) {
        nil
    }

    /// Whether the pill casts its own shadows.
    ///
    /// It does not, while it is glass: the platform lights and shades a pane
    /// of its own accord, and a hand-cast shadow under one is a second lift
    /// disagreeing with the first. It does when it cannot be glass, because
    /// then it is a cream capsule on a cream page and nothing else says it is
    /// in front.
    func lifted(_ casting: Bool) {
        for shadow in shadows { shadow.isHidden = !casting }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The pane rounds itself; what is left is the shadows underneath it,
        // cast in the outline it rounded to.
        Elevation.shape(
            shadows,
            like: UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2),
            in: bounds
        )
    }
}
