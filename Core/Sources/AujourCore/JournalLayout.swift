/// Which of Aujour's two presentations the journal is being read in — decided
/// by how wide the window is, and by nothing else.
///
/// Aujour ships one app for iPhone and iPad, and the difference between them
/// is not a difference between devices: an iPad in Slide Over has no more room
/// than a phone. So the question the app asks is what shape *this window* is,
/// and both presentations ship on both families.
///
/// A size class is not enough to ask it with, and that is the reason these are
/// numbers of points. An iPad mini in portrait reports a regular width at 744,
/// which is too narrow to hold a calendar and a page of readable prose at the
/// same time — a split there would leave the Entry narrower than it is on a
/// phone.
///
/// And a width is not enough on its own, which is the other half of the same
/// thought: a room has two measurements. An iPhone on its side is wide enough
/// for a sidebar and nowhere near tall enough for the month that would go in
/// it.
///
/// Here rather than in the view for the reason ``DatePill`` is: where the line
/// falls is a decision, and a decision that only exists inside a
/// `GeometryReader` is one nothing can ask a question about.
public enum JournalLayout: Equatable, Sendable {
    /// The Entry across the whole window, with the date pill over it — the
    /// pill being the answer to having no room for a calendar, and so what a
    /// narrow window gets whatever it is running on.
    case page

    /// The month grid down one side and the Entry beside it, set at a
    /// comfortable measure rather than stretched across the window.
    case sidebar

    /// How wide a window has to be before it can hold a calendar and a page of
    /// readable prose at once.
    ///
    /// Roughly a portrait iPad: below it are Slide Over, a half-width Split
    /// View, a dragged-narrow Stage Manager window and an iPad mini stood up,
    /// all of which are phone-shaped rooms whatever they are running on.
    public static let sidebarNeedsWidth: Double = 820

    /// And how tall, because a calendar that is always on screen has to fit on
    /// screen: six weeks of a month, the weekday initials over them, the
    /// month's own name over those and the day being written over all of it.
    ///
    /// Which is the case a width alone gets wrong, and it is a phone on its
    /// side: an iPhone in landscape is wide enough for two columns and 400
    /// points short of the height to put a month in one. Handing it a sidebar
    /// would be handing it a calendar it had to scroll, beside a page four
    /// lines deep — when the pill it already has was designed for exactly that
    /// room.
    ///
    /// A short Stage Manager window is the same answer for the same reason, so
    /// this is still a fact about the window and not about the device.
    public static let sidebarNeedsHeight: Double = 600

    /// How many characters wide the Entry is set where the window is wide
    /// enough for the measure to be a choice.
    ///
    /// A measure and not a fraction of the window: what makes a line easy to
    /// come back from is how many characters are on it, so this is counted in
    /// characters and turned into points by whatever face the reader is
    /// writing in. Below the threshold there is nothing to cap — the window is
    /// already narrower than this.
    public static let measure: Double = 65

    /// - Parameters:
    ///   - windowWidth: how wide the window is, in points. The *window*, never
    ///     the screen: the app is given a width, and where that width came
    ///     from is the system's business.
    ///   - windowHeight: and how tall, for the same reason. A room has two
    ///     measurements and a sidebar needs both — one to sit beside a page of
    ///     readable prose, and one to be a whole month while it does.
    public init(windowWidth: Double, windowHeight: Double) {
        self =
            windowWidth >= Self.sidebarNeedsWidth && windowHeight >= Self.sidebarNeedsHeight
            ? .sidebar
            : .page
    }
}
