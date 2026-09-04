import AujourCore
import SwiftUI
import UIKit

/// How Aujour looks on this device, as something the user can change: the
/// appearance, the accent, and the typeface their days are written in.
///
/// A page of its own rather than three more rows on the sheet, because the
/// appearance, the accent and the typeface are one question asked three ways
/// and the sheet is a list of separate ones.
///
/// A grouped `Form`, like every other settings screen: three sections, each
/// headed with the one word it is about, and nothing said in prose. The notes
/// this page used to carry — what Auto follows, that the size control is the
/// entry's alone, that none of this reaches the other devices — are gone. Two
/// of the three are answered by the controls themselves the moment they are
/// touched, and the third was answering a question the sheet no longer sets
/// out to raise.
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

    var body: some View {
        Form {
            appearanceSection
            accentSection
            editorFontSection
        }
        .settingsPage(titled: "Appearance")
    }

    // MARK: - Light, dark, or the system's

    private var appearanceSection: some View {
        Section("Theme") {
            Picker("Theme", selection: chosenTheme) {
                ForEach(Theme.asOffered, id: \.self) { theme in
                    Text(theme.name).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearanceTheme")
        }
    }

    private var chosenTheme: Binding<Theme> {
        Binding(get: { appearance.theme }, set: { appearance.use($0) })
    }

    // MARK: - The one colour the app spends on itself

    private var accentSection: some View {
        Section("Accent") {
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
            .frame(maxWidth: .infinity, alignment: .leading)

            // What the swatches cannot say out loud, and what a test asks for:
            // which of the nine is the one in force. In that accent's own ink
            // — the shade the identity keeps for accent-coloured words — so
            // the name is legible whichever colour it is naming.
            Text(appearance.accent.name)
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
        Section("Editor font") {
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
            .accessibilityIdentifier("editorFontSpecimen")
            // What the specimen shows and a test cannot read off it: which
            // face, at what size.
            .accessibilityValue(
                "\(appearance.editorFont.family.name), \(appearance.editorFont.size.name)"
            )
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
