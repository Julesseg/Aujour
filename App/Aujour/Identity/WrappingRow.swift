import SwiftUI

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
