import Testing

@testable import AujourCore

/// Which of Aujour's two presentations a window gets, which is a question
/// about the window and not about the device it is on.
///
/// Here rather than in the view because it is a decision with two numbers in
/// it, and a number buried in a `GeometryReader` is one nothing can ask about.
/// The windows below are real ones — the rooms an iPhone and an iPad actually
/// hand an app — so that the rule is held to the cases it was written for
/// rather than to a few round numbers either side of a line.
@Suite("The layout a window is the shape for")
struct JournalLayoutTests {
    /// A window, named for the room it is.
    struct Window {
        let name: String
        let width: Double
        let height: Double

        var layout: JournalLayout {
            JournalLayout(windowWidth: width, windowHeight: height)
        }
    }

    private static let tallEnough = JournalLayout.sidebarNeedsHeight
    private static let wideEnough = JournalLayout.sidebarNeedsWidth

    @Test("a window narrower than the threshold gets the page")
    func aNarrowWindowGetsThePage() {
        let layout = JournalLayout(
            windowWidth: Self.wideEnough - 1,
            windowHeight: Self.tallEnough
        )

        #expect(layout == .page)
    }

    @Test("a window shorter than the threshold gets the page, however wide")
    func aShortWindowGetsThePage() {
        let layout = JournalLayout(
            windowWidth: Self.wideEnough * 2,
            windowHeight: Self.tallEnough - 1
        )

        #expect(layout == .page)
    }

    @Test("a window at both thresholds gets the sidebar")
    func aWindowAtTheThresholdsGetsTheSidebar() {
        #expect(
            JournalLayout(windowWidth: Self.wideEnough, windowHeight: Self.tallEnough) == .sidebar
        )
        #expect(
            JournalLayout(windowWidth: Self.wideEnough + 1, windowHeight: Self.tallEnough + 1)
                == .sidebar
        )
    }

    /// A window has a size before it has a shape, and nought is a size like any
    /// other: the page is what an app with no room is, and a sidebar squeezed
    /// into nothing would be a first frame with no journal in it.
    @Test("a window with no size yet gets the page")
    func aWindowWithNoSizeGetsThePage() {
        #expect(JournalLayout(windowWidth: 0, windowHeight: 0) == .page)
    }

    /// The two cases a size class alone gets wrong, and the reason this is
    /// measured in points: an iPad mini in portrait reports *regular* width at
    /// 744, where a sidebar would leave the Entry narrower than a phone's — and
    /// a phone on its side is wide enough for a sidebar and 400 points short of
    /// the height to put a month in one.
    @Test(
        "the windows with no room for a calendar beside a page get the page",
        arguments: [
            Window(name: "iPhone 16 Pro, portrait", width: 402, height: 874),
            Window(name: "iPhone 16 Pro, landscape", width: 874, height: 402),
            Window(name: "iPhone 16 Pro Max, landscape", width: 956, height: 440),
            Window(name: "Slide Over", width: 320, height: 1133),
            Window(name: "a third of an iPad, landscape", width: 375, height: 1024),
            Window(name: "half an iPad Pro 13\", landscape", width: 678, height: 1024),
            Window(name: "iPad mini, portrait", width: 744, height: 1133),
            Window(name: "a short Stage Manager window", width: 1000, height: 500),
        ]
    )
    private func theRoomsWithoutTheShapeGetThePage(window: Window) {
        #expect(window.layout == .page, "\(window.name)")
    }

    @Test(
        "the windows with room for a calendar and a page get the sidebar",
        arguments: [
            Window(name: "iPad, portrait", width: 820, height: 1180),
            Window(name: "iPad Pro 11\", portrait", width: 834, height: 1210),
            Window(name: "iPad mini, landscape", width: 1133, height: 744),
            Window(name: "iPad Pro 13\", landscape", width: 1366, height: 1024),
        ]
    )
    private func theRoomsWithBothGetTheSidebar(window: Window) {
        #expect(window.layout == .sidebar, "\(window.name)")
    }

    /// The threshold is a window's and not a screen's, which is the whole of
    /// what makes Slide Over and a half-width Split View phone-shaped: one
    /// iPad hands the app four different rooms in an afternoon, and the
    /// presentation follows the room each time.
    @Test("one iPad gets both presentations, by the shape of the window")
    func oneDeviceGetsBothPresentations() {
        // An iPad Pro 13" in landscape, as the app is given it: the whole
        // screen, two thirds of it, half of it, and Slide Over.
        let windows = [
            Window(name: "full screen", width: 1366, height: 1024),
            Window(name: "two thirds", width: 981, height: 1024),
            Window(name: "half", width: 678, height: 1024),
            Window(name: "Slide Over", width: 375, height: 1024),
        ]
        let presentations: [JournalLayout] = [.sidebar, .sidebar, .page, .page]

        #expect(windows.map(\.layout) == presentations)
    }

    /// And one phone gets one presentation, whichever way up it is held. A
    /// landscape iPhone clears the width and misses the height by 400 points:
    /// the pill it already has was designed for exactly that room.
    @Test("a phone gets the page whichever way it is held")
    func aPhoneAlwaysGetsThePage() {
        let windows = [
            Window(name: "portrait", width: 402, height: 874),
            Window(name: "landscape", width: 874, height: 402),
        ]

        #expect(windows.allSatisfy { $0.layout == .page })
    }
}
