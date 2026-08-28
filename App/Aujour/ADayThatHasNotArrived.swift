import AujourCore
import SwiftUI

/// A day the journal has been walked to and the clock has not reached.
///
/// The one page in Aujour with no editor on it, and that is the whole of what
/// it is: there is no Entry to write before the day has arrived
/// (`CONTEXT.md`), so a day that has not begun is a day the app has nothing to
/// put a caret in. Drawn rather than merely refused, because a swipe that did
/// nothing at the end of today would read as a swipe that had broken.
///
/// It says when writing opens, and it says it as an hour on the reader's own
/// clock — which is the Rollover Hour, the setting that decides when a Journal
/// Day turns. Without it "not yet" is a wall; with it, it is a time.
///
/// No way out on it. The way back is on the pill above: the Today chip, which
/// is there the whole time the app is not on today, and the same sideways
/// swipe that got here drawn the other way.
struct ADayThatHasNotArrived: View {
    /// When the Journal Day turns, and so when this day begins.
    ///
    /// The whole of what this page needs. Which day it is over is not among
    /// its parts: the pill directly above is naming that day already, and
    /// every day that has not arrived says exactly this one thing.
    let writingOpensAt: RolloverHour

    var body: some View {
        ContentUnavailableView {
            // Not named here: the pill directly above is naming this day
            // already, and a screen that says the date twice in two typefaces
            // is the redesign's own worst page.
            Label("This day hasn't started yet", systemImage: "calendar.badge.clock")
                .accessibilityIdentifier("aDayThatHasNotArrived")
        } description: {
            Text(
                "Your day turns at \(writingOpensAt.spelledOut()), and writing opens then. "
                    + "There's nothing to write in a day before it has begun."
            )
            .accessibilityIdentifier("whenWritingOpens")
        }
        // The whole of the page, because that is what this is: the day's own
        // words are not underneath it waiting to be uncovered, there are none.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Tomorrow") {
    ADayThatHasNotArrived(writingOpensAt: RolloverHour(hour: 4)!)
        .background(Palette.backgroundColor)
}
