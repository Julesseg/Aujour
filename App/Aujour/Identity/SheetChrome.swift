import SwiftUI

/// The pieces every sheet in Aujour is built out of: the paper it is cut from,
/// the corner it is cut with, the grabber at the top of it, and the way it
/// arrives from the control that summoned it.
///
/// Shared rather than repeated, for `SettingsChrome`'s reason: a sheet is one
/// of the two shapes this app has — a page, and something in front of a page —
/// and two sheets that came up differently would say they were two apps. What
/// a sheet is *about* is its own; what it looks like on the way in is not.

/// What a sheet and the control that summons it agree to call the journey
/// between them.
///
/// Named in one place rather than spelled out at both ends: a sheet whose
/// identifier does not match its button's does not fail — it quietly comes up
/// from the bottom of the screen instead, which is the kind of wrong nobody
/// notices for a release.
enum Sheets {
    static let search = "search"
    static let settings = "settings"
    static let share = "share"
}

extension View {
    /// Dresses a sheet in the identity: the paper, the corner and the grabber.
    ///
    /// The identity's own sheet paper, which is a hair off the page's so that
    /// a sheet over a screen reads as being in front of it. The corner is much
    /// rounder than anything drawn on a page, because it is the one corner cut
    /// against the device's own (`Rounding.sheet`).
    ///
    /// The grabber is the system's rather than a bar of the identity's own
    /// drawing: it is the thing that moves under the finger dragging the
    /// sheet, and one drawn here would be a picture of that.
    ///
    /// The scrim is the system's too, and there is no seam to replace it —
    /// which is no loss. What the design file draws behind a sheet is a dim
    /// and a slight blur, and that is what a sheet already comes up over.
    ///
    /// Nothing here tints anything: the accent this device chose is already on
    /// the whole app, and a sheet inherits the environment of the view that put
    /// it up.
    ///
    /// How *tall* a sheet is stays the caller's, because it is a fact about
    /// what is on it — a search box over a list is not a page of settings.
    func sheetChrome() -> some View {
        presentationBackground(Palette.sheetColor)
            .presentationCornerRadius(Rounding.sheet)
            .presentationDragIndicator(.visible)
    }

    /// The same chrome, on a sheet that rises out of the control that summoned
    /// it.
    ///
    /// The control has to be marked as the place it comes from, with
    /// ``SwiftUI/View/matchedTransitionSource(id:in:)`` under the same
    /// identifier and namespace. Where it is not — the control has scrolled
    /// away, or the sheet was put up by something else — the sheet comes up
    /// the ordinary way, which is why nothing here has to check.
    func sheetChrome(risingFrom id: some Hashable & Sendable, in namespace: Namespace.ID)
        -> some View
    {
        navigationTransition(.zoom(sourceID: id, in: namespace))
            .sheetChrome()
    }
}

/// A choice between two or three things that are the same kind of thing, laid
/// out as one control: the trough, and the chosen one raised out of it.
///
/// The identity's own rather than the system's segmented control, because it
/// is on a sheet whose whole job is to show what a choice *looks like* — and a
/// grey iOS segment over the identity's paper is the one thing on that sheet
/// that would still belong to somebody else's app.
///
/// The tokens were cut for it: `Rounding.control` is "a field, a segmented
/// trough, a photo tile", and `Elevation.resting` is "a slider's thumb, a
/// segmented control's selected segment".
struct SegmentedChoice<Option: Hashable>: View {
    let options: [Option]
    @Binding var chosen: Option

    /// What each option is called, and what a test asks for it by.
    let name: (Option) -> String
    let identifier: (Option) -> String

    var body: some View {
        HStack(spacing: Spacing.tight) {
            ForEach(options, id: \.self) { option in
                Button { chosen = option } label: {
                    Text(name(option))
                        .lettering(.chipLabel)
                        .foregroundStyle(
                            option == chosen ? Palette.inkColor : Palette.inkMutedColor
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.close)
                        .background {
                            if option == chosen {
                                RoundedRectangle(cornerRadius: Rounding.control - Spacing.tight)
                                    .fill(Palette.cardColor)
                                    .elevated(.resting)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier(option))
                // What a segment cannot say by being raised: that it is the
                // one in force.
                .accessibilityAddTraits(option == chosen ? [.isSelected] : [])
            }
        }
        .padding(Spacing.tight)
        .background(Palette.fieldColor, in: RoundedRectangle(cornerRadius: Rounding.control))
    }
}

/// A row of small things that wraps onto as many lines as it costs.
///
/// Wrapped rather than scrolled sideways, for the accent swatches' reason: a
/// set with some of it behind a gesture nobody knows is there is a set with
/// some of it missing. And laid out by measuring rather than by a grid,
/// because these are words — a grid of equal columns would make `fig` as wide
/// as `mood: 5`, which is a row of chips pretending to be a table.
struct WrappingRow: Layout {
    var spacing: CGFloat = Spacing.close

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let lines = lines(of: subviews, within: width)
        let height =
            lines.reduce(0) { $0 + $1.height }
            + spacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for line in lines(of: subviews, within: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    /// One line of the row: which of the subviews are on it, and how tall the
    /// tallest of them is.
    private struct Line {
        var indices: [Subviews.Index] = []
        var height: CGFloat = 0
    }

    /// How the subviews fall into lines at this width — worked out the same
    /// way for measuring and for placing, so that the two cannot disagree.
    private func lines(of subviews: Subviews, within width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        var x: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            // Never a line with nothing on it: one chip wider than the whole
            // row still has to be drawn somewhere, and a line of its own is
            // where.
            if !line.indices.isEmpty, x + size.width > width {
                lines.append(line)
                line = Line()
                x = 0
            }
            line.indices.append(index)
            line.height = max(line.height, size.height)
            x += size.width + spacing
        }
        if !line.indices.isEmpty { lines.append(line) }
        return lines
    }
}
