import Testing

@testable import AujourCore

/// Which of Aujour's two presentations a window gets, which is a question
/// about the window and not about the device it is on.
///
/// Here rather than in the view because it is a decision with a number in it,
/// and a number buried in a `GeometryReader` is one nothing can ask about. The
/// widths below are real ones — the windows an iPad actually hands an app —
/// so that the rule is held to the cases it was written for rather than to
/// three round numbers either side of the threshold.
@Suite("The layout a window is wide enough for")
struct JournalLayoutTests {
    @Test("a window narrower than the threshold gets the page")
    func aNarrowWindowGetsThePage() {
        #expect(JournalLayout(windowWidth: JournalLayout.sidebarNeeds - 1) == .page)
    }

    @Test("a window at the threshold gets the sidebar")
    func aWindowAtTheThresholdGetsTheSidebar() {
        #expect(JournalLayout(windowWidth: JournalLayout.sidebarNeeds) == .sidebar)
        #expect(JournalLayout(windowWidth: JournalLayout.sidebarNeeds + 1) == .sidebar)
    }

    /// A window has a width before it has a size, and nought is a width like
    /// any other: the page is what an app with no room is, and a sidebar
    /// squeezed into nothing would be a first frame with no journal in it.
    @Test("a window with no width yet gets the page")
    func aWindowWithNoWidthGetsThePage() {
        #expect(JournalLayout(windowWidth: 0) == .page)
    }

    /// The case a size class alone gets wrong, and the reason this is measured
    /// in points: an iPad mini in portrait reports *regular* width at 744, and
    /// a sidebar there would leave the Entry narrower than a phone's.
    @Test(
        "the windows that are too narrow for a sidebar get the page",
        arguments: [
            ("iPhone 16 Pro, portrait", 402.0),
            ("iPhone 16 Pro Max, portrait", 440.0),
            ("Slide Over", 320.0),
            ("iPad mini, portrait", 744.0),
            ("a third of an iPad, landscape", 375.0),
            ("half an iPad Pro 13\", landscape", 678.0),
        ]
    )
    func theNarrowWindowsGetThePage(window: (name: String, width: Double)) {
        #expect(JournalLayout(windowWidth: window.width) == .page, "\(window.name)")
    }

    @Test(
        "the windows with room for a calendar and a page get the sidebar",
        arguments: [
            ("iPad, portrait", 820.0),
            ("iPad Pro 11\", portrait", 834.0),
            ("iPad mini, landscape", 1133.0),
            ("iPad Pro 13\", landscape", 1366.0),
        ]
    )
    func theWideWindowsGetTheSidebar(window: (name: String, width: Double)) {
        #expect(JournalLayout(windowWidth: window.width) == .sidebar, "\(window.name)")
    }

    /// The threshold is a window's and not a screen's, which is the whole of
    /// what makes Slide Over and a half-width Split View phone-shaped: one
    /// iPad hands the app four different widths in an afternoon, and the
    /// presentation follows the window each time.
    @Test("one iPad gets both presentations, by how wide the window is")
    func oneDeviceGetsBothPresentations() {
        // An iPad Pro 13" in landscape, as the app is given it: the whole
        // screen, two thirds of it, half of it, and Slide Over.
        let windows = [1366.0, 981.0, 678.0, 375.0]

        let presentations: [JournalLayout] = [.sidebar, .sidebar, .page, .page]

        #expect(windows.map(JournalLayout.init(windowWidth:)) == presentations)
    }
}
