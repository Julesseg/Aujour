import SwiftUI

/// The pieces of chrome the settings screens are built out of: the small
/// capitals over a group of controls, the sentence under one saying what it
/// does, and the line between two groups.
///
/// Shared rather than repeated, because they are the identity and not a
/// screen's own idea: the settings sheet and the appearance page are one door
/// and a step further in, and a sentence that was `.caption` and `.secondary`
/// on one and note-on-muted-ink on the other would say they were two apps.

/// The small capitals over a group of controls.
///
/// In the faintest ink, which is what that ink is for: a header is a label on
/// a section and never a sentence, so it is held to the marker floor rather
/// than the sentence one (ADR 0006, and `Palette.inkFaint`).
struct SectionHeader: View {
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
struct Note: View {
    let words: String

    init(_ words: String) { self.words = words }

    var body: some View {
        Text(words)
            .lettering(.note)
            .foregroundStyle(Palette.inkMutedColor)
    }
}

/// The line between two groups.
///
/// The identity's own hairline rather than `Divider()`, which draws in the
/// system's separator grey and is the one thing on a settings screen that
/// would still look like somebody else's app.
///
/// One device pixel, so the line is as thin as the screen can draw rather than
/// as thin as a point — which on a 3× phone is three of them.
struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Palette.ruleColor)
            .frame(height: 1 / displayScale)
    }
}
