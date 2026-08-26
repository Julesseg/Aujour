import AujourCore
import SwiftUI
import UIKit

/// How Aujour looks on this device, as something the user can change: the
/// appearance, the accent, and the typeface their days are written in.
///
/// A page of its own beside the journal's settings rather than a section in
/// them, because it answers a different question. Everything on the journal's
/// page shapes what is written into the folder and therefore has to agree
/// across the user's devices; nothing here shapes a file at all, so nothing
/// here travels (ADR 0003). A dark iPhone and a light iPad are both right, and
/// a page that mixed the two kinds would be quietly promising otherwise.
///
/// It changes the appearance by asking it, and shows what the appearance
/// answers — there is no copy of a choice here for the screen to disagree
/// with. Every control is over the same object the whole app is drawn from, so
/// a tap on a swatch is the app's colour before the finger is off it.
///
/// This is also the screen the identity's token layer is proved on. Nothing
/// here names a colour, a corner or a size — every one of them is a role asked
/// of `Palette`, `Rounding`, `Spacing` or `Lettering`, so that re-cutting the
/// identity is an edit to those four files and not a search through the app.
/// Two things on the page are deliberately not tokenised: the segmented
/// controls, which SwiftUI draws in the platform's own idiom and which nothing
/// here should be repainting, and the specimen's own typeface, which is the
/// choice being made rather than a size the identity has a say in.
struct AppearanceSettingsView: View {
    let appearance: DeviceAppearance

    /// "iPhone" or "iPad" — this page is about this device, and saying which
    /// one is what makes "and not the other one" true rather than implied.
    private var device: String { UIDevice.current.model }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.apart) {
                appearanceSection
                rule
                accentSection
                rule
                editorFontSection
                rule
                Text(
                    """
                    These stay on this \(device). Your other devices keep their \
                    own — nothing here changes a word in your journal folder.
                    """
                )
                .lettering(.note)
                .foregroundStyle(Palette.inkMutedColor)
                .accessibilityIdentifier("appearanceIsDeviceLocal")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.apart)
        }
        .background(Palette.backgroundColor)
        .navigationTitle("How it looks")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The identity's own hairline rather than `Divider()`, which draws in the
    /// system's separator grey and is the one thing on this page that would
    /// still look like somebody else's app.
    ///
    /// One device pixel, so the line is as thin as the screen can draw rather
    /// than as thin as a point — which on a 3× phone is three of them.
    private var rule: some View {
        Rectangle()
            .fill(Palette.ruleColor)
            .frame(height: 1 / displayScale)
    }

    @Environment(\.displayScale) private var displayScale

    // MARK: - Light, dark, or the system's

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.close) {
            SectionHeader("Appearance")

            Picker("Appearance", selection: chosenTheme) {
                ForEach(Theme.allCases, id: \.self) { theme in
                    Text(theme.name).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearanceTheme")

            Note(
                """
                Auto follows this \(device) — light through the day, dark at \
                night if that is how it is set.
                """
            )
        }
    }

    private var chosenTheme: Binding<Theme> {
        Binding(get: { appearance.theme }, set: { appearance.use($0) })
    }

    // MARK: - The one colour the app spends on itself

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.close) {
            SectionHeader("Accent")

            // Wrapped rather than scrolled or squeezed. Nine of these do not
            // fit across a phone, and the two ways of pretending they do are
            // both worse than a second row: shrinking them to fit makes nine
            // colours hard to tell apart at the size they are being judged at,
            // and scrolling them sideways hides some of the set behind a
            // gesture nobody knows is there. So they take the width they need
            // and wrap onto as many rows as that costs — which is also what
            // keeps them laid out at the largest accessibility size, where a
            // swatch is half again as wide and a row holds four of them.
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: swatchSize + Spacing.comfortable),
                        spacing: Spacing.comfortable,
                        alignment: .leading
                    )
                ],
                alignment: .leading,
                spacing: Spacing.comfortable
            ) {
                ForEach(Accent.allCases, id: \.self) { accent in
                    AccentSwatch(
                        accent: accent,
                        size: swatchSize,
                        chosen: accent == appearance.accent
                    ) {
                        appearance.use(accent)
                    }
                }
            }

            // What the swatches cannot say out loud, and what a test asks for:
            // which of the nine is the one in force. In that accent's own ink
            // — the shade the identity keeps for accent-coloured words — so
            // the name is legible whichever colour it is naming.
            Text(appearance.accent.name)
                .lettering(.rowValue)
                .foregroundStyle(appearance.accent.ink)
                .accessibilityIdentifier("accentInUse")
        }
    }

    /// A swatch grows with the system text size like everything else on the
    /// page. It carries no words, so it does not have to — but a control sized
    /// in fixed points beside labels that have doubled is a control that has
    /// quietly become the hardest thing on the screen to hit.
    @ScaledMetric(relativeTo: .body) private var swatchSize: CGFloat = 32

    // MARK: - What the days are written in

    private var editorFontSection: some View {
        VStack(alignment: .leading, spacing: Spacing.close) {
            SectionHeader("Editor font")

            Picker("Editor font", selection: chosenFamily) {
                ForEach(EditorFont.Family.allCases, id: \.self) { family in
                    Text(family.name).tag(family)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("editorFontFamily")

            Picker("Text size", selection: chosenSize) {
                ForEach(EditorFont.Size.allCases, id: \.self) { size in
                    Text(size.name).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("editorFontSize")

            specimen

            Note(
                """
                How big your own words are. Everything else in Aujour follows \
                the text size on this \(device); this is the entry alone, and \
                it moves with that too.
                """
            )
        }
    }

    private var chosenFamily: Binding<EditorFont.Family> {
        Binding(get: { appearance.editorFont.family }, set: { appearance.useEditorFont($0) })
    }

    private var chosenSize: Binding<EditorFont.Size> {
        Binding(
            get: { appearance.editorFont.size },
            set: { appearance.useEditorFont(sized: $0) }
        )
    }

    /// A line of a journal in the typeface being chosen, because that is the
    /// only honest way to offer one: "Serif, 19 pt" is a description of a
    /// decision somebody then has to picture, and this is the decision itself.
    ///
    /// The one piece of lettering on the page that is not on the identity's
    /// scale, and that is the point of it. Everything else here follows the
    /// system's text size; this follows the S/M/L/XL control above it, because
    /// what it is showing *is* that control's answer.
    private var specimen: some View {
        Text("Walked to the market, and the morning was already warm.")
            .font(Font(appearance.editorFont.uiFont(compatibleWith: nil)))
            .foregroundStyle(Palette.inkColor)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.comfortable)
            .background(Palette.cardColor, in: RoundedRectangle(cornerRadius: Rounding.card))
            .elevated(.resting)
            .accessibilityIdentifier("editorFontSpecimen")
            // What the specimen shows and a test cannot read off it: which
            // face, at what size.
            .accessibilityValue(
                "\(appearance.editorFont.family.name), \(appearance.editorFont.size.name)"
            )
    }
}

/// The small capitals over a group of controls.
///
/// In the faintest ink, which is what that ink is for: a header is a label on
/// a section and never a sentence, so it is held to the marker floor rather
/// than the sentence one (ADR 0006, and `Palette.inkFaint`).
private struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .lettering(.sectionHeader)
            .foregroundStyle(Palette.inkFaintColor)
            .textCase(.uppercase)
    }
}

/// The sentence under a control that says what it does.
///
/// In the muted ink and not the faint one, however much the design file wants
/// it quiet: this is prose the reader is meant to read, and a sentence clears
/// 4.5:1 (ADR 0006).
private struct Note: View {
    let words: String

    init(_ words: String) { self.words = words }

    var body: some View {
        Text(words)
            .lettering(.note)
            .foregroundStyle(Palette.inkMutedColor)
    }
}

/// One colour on offer: the colour itself, ringed when it is the one in force.
///
/// A filled circle and not a labelled row, because nine of these fit on two
/// lines and a colour is the only thing a colour has to say. The name is on it
/// for VoiceOver, which cannot see the fill.
private struct AccentSwatch: View {
    let accent: Accent
    let size: CGFloat
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            Circle()
                .fill(accent.color)
                .frame(width: size, height: size)
                .overlay {
                    // Drawn in the card's own colour rather than the accent's,
                    // so the tick is legible on every one of the nine and in
                    // both appearances — every accent clears 4.5:1 against the
                    // card, which is the same measurement read the other way
                    // round.
                    if chosen {
                        // On the chip role rather than the marker one, so the
                        // tick grows at the same rate as the circle under it —
                        // the swatch follows `.body` and the smallest roles on
                        // the scale top out well below that.
                        Image(systemName: "checkmark")
                            .lettering(.chipLabel)
                            .fontWeight(.bold)
                            .foregroundStyle(Palette.cardColor)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(accent.color, lineWidth: chosen ? 2 : 0)
                        .padding(-Spacing.tight)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("accent.\(accent.rawValue)")
        .accessibilityLabel(accent.name)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView(appearance: .inMemory())
    }
}
