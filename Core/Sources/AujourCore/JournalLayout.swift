/// Which of Aujour's two presentations the journal is being read in — decided
/// by how wide the window is, and by nothing else.
///
/// Aujour ships one app for iPhone and iPad, and the difference between them
/// is not a difference between devices: an iPad in Slide Over has no more room
/// than a phone, and a phone laid on its side can have more room than an iPad
/// mini stood up. So the question the app asks is how wide *this window* is,
/// and both presentations ship on both families.
///
/// A size class is not enough to ask it with, and that is the reason this is a
/// number of points. An iPad mini in portrait reports a regular width at 744,
/// which is too narrow to hold a calendar and a page of readable prose at the
/// same time — a split there would leave the Entry narrower than it is on a
/// phone.
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
    public static let sidebarNeeds: Double = 820

    /// How many characters wide the Entry is set where the window is wide
    /// enough for the measure to be a choice.
    ///
    /// A measure and not a fraction of the window: what makes a line easy to
    /// come back from is how many characters are on it, so this is counted in
    /// characters and turned into points by whatever face the reader is
    /// writing in. Below the threshold there is nothing to cap — the window is
    /// already narrower than this.
    public static let measure: Double = 65

    /// - Parameter windowWidth: how wide the window is, in points. The
    ///   *window*, never the screen: the app is given a width, and where that
    ///   width came from is the system's business.
    public init(windowWidth: Double) {
        self = windowWidth >= Self.sidebarNeeds ? .sidebar : .page
    }
}
