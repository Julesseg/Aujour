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
struct AppearanceSettingsView: View {
    let appearance: DeviceAppearance

    /// "iPhone" or "iPad" — this page is about this device, and saying which
    /// one is what makes "and not the other one" true rather than implied.
    private var device: String { UIDevice.current.model }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appearanceSection
                Divider()
                accentSection
                Divider()
                editorFontSection
                Divider()
                Text(
                    """
                    These stay on this \(device). Your other devices keep their \
                    own — nothing here changes a word in your journal folder.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("appearanceIsDeviceLocal")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("How it looks")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Light, dark, or the system's

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Appearance")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Appearance", selection: chosenTheme) {
                ForEach(Theme.allCases, id: \.self) { theme in
                    Text(theme.name).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearanceTheme")

            Text(
                """
                Auto follows this \(device) — light through the day, dark at \
                night if that is how it is set.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var chosenTheme: Binding<Theme> {
        Binding(get: { appearance.theme }, set: { appearance.use($0) })
    }

    // MARK: - The one colour the app spends on itself

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accent")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            // Wrapped rather than scrolled or squeezed. Nine of these do not
            // fit across a phone, and the two ways of pretending they do are
            // both worse than a second row: shrinking them to fit makes nine
            // colours hard to tell apart at the size they are being judged at,
            // and scrolling them sideways hides some of the set behind a
            // gesture nobody knows is there. So they take the width they need
            // and wrap onto as many rows as that costs.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 44), spacing: 12, alignment: .leading)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(Accent.allCases, id: \.self) { accent in
                    AccentSwatch(accent: accent, chosen: accent == appearance.accent) {
                        appearance.use(accent)
                    }
                }
            }

            // What the swatches cannot say out loud, and what a test asks for:
            // which of the six is the one in force.
            Text(appearance.accent.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("accentInUse")
        }
    }

    // MARK: - What the days are written in

    private var editorFontSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Editor font")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

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

            Text(
                """
                How big your own words are. Everything else in Aujour follows \
                the text size on this \(device); this is the entry alone, and \
                it moves with that too.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
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
    private var specimen: some View {
        Text("Walked to the market, and the morning was already warm.")
            .font(Font(appearance.editorFont.uiFont(compatibleWith: nil)))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
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
/// A filled circle and not a labelled row, because six of these fit on one
/// line and a colour is the only thing a colour has to say. The name is on it
/// for VoiceOver, which cannot see the fill.
private struct AccentSwatch: View {
    let accent: Accent
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            Circle()
                .fill(accent.color)
                .frame(width: 32, height: 32)
                .overlay {
                    // Drawn in the page's own colour rather than the accent's,
                    // so the tick is legible on every one of the six and in
                    // both appearances.
                    if chosen {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.background)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(accent.color, lineWidth: chosen ? 2 : 0)
                        .padding(-4)
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
