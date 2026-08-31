import SwiftUI
import AujourCore

/// The three pages a fresh install opens on, over a journal that is already
/// opening behind them.
///
/// Not a setup wizard, and deliberately not one: Aujour finds a folder and
/// spawns today's Entry without being told anything (ADR 0004), so there is
/// nothing here that has to be answered before the app works. Every page can
/// be left, the last one's offer can be declined, and what is behind all three
/// is the day the user came to write.
///
/// It says three things and no more — what this is, where the words will be,
/// and the one thing Aujour would ever do while nobody is looking. The rest of
/// what the app can be told is on the journal sheet, where somebody goes when
/// they want it rather than in the first thirty seconds when they do not.
///
/// The view holds no rules. Which page is on screen, what the ends of the
/// sequence do and what the offer means are ``Welcome``'s, in Core, where they
/// are tested without a simulator.
struct WelcomeView: View {
    let journal: Journal

    /// The time the offer is sitting on — a starting point, not a default: it
    /// becomes a reminder only if the button under it is pressed.
    @State private var time = DailyReminder.suggestedTime

    private var welcome: Welcome { journal.welcome }

    /// "iPhone" or "iPad" — the app runs on both, and the folder is named
    /// after whichever this is.
    private var device: String { UIDevice.current.model }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Centred in the room above the buttons, and scrollable when
                // there is not enough of it: three short pages stranded at the
                // top of a phone read as a screen that has not finished
                // loading, and the same three at a large Dynamic Type size are
                // taller than the screen.
                GeometryReader { room in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            page
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, Spacing.apart)
                                .padding(.vertical, Spacing.apart)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: room.size.height)
                    }
                    // What a test walks when it is looking for a page that has
                    // come apart: the pages are one scrolling view whichever of
                    // the three is in it, and "the first scroll view in the
                    // app" is not a promise anybody made while the day is open
                    // behind this cover.
                    .accessibilityIdentifier("welcomePage")
                }
                howFarThroughItThisIs
                waysOn
                    .padding(.horizontal, Spacing.apart)
                    .padding(.bottom, Spacing.comfortable)
            }
            // The identity's own paper, which is what the whole cover is: this
            // is not a sheet over a screen — there is nothing behind it to
            // read as being behind it — so it takes the page's ground rather
            // than the sheet's.
            .background(Palette.backgroundColor)
            // A bare bar with one button in it: there is no title here, and a
            // large one's empty room would push three short pages down the
            // screen for nothing.
            .navigationBarTitleDisplayMode(.inline)
            // The same paper again, so that a page long enough to scroll —
            // which is every one of them once the reader has turned the text
            // up — does not slide under a band of the system's own grey. The
            // bar is invisible either way; what this decides is that it stays
            // invisible when there is something under it.
            .toolbarBackground(Palette.backgroundColor, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Only where there is still something ahead: on the last
                    // page the offer's own "Not now" is the same door, and two
                    // buttons for one answer is a decision made twice.
                    if !welcome.isOnTheLastPage {
                        Button("Skip") { end(remindingAt: nil) }
                            .accessibilityIdentifier("skipTheWelcome")
                    }
                }
            }
        }
        // Not dismissible by a swipe, and with no way out that is not one of
        // the buttons: the welcome ends when it has been answered, and an
        // accidental drag would leave somebody in an app that had just been
        // about to say where their files are.
        .interactiveDismissDisabled()
        .presentationBackground(Palette.backgroundColor)
    }

    @ViewBuilder
    private var page: some View {
        switch welcome.page {
        case .whatThisIs:
            WelcomePage(
                symbol: "book.pages",
                title: "One day at a time",
                identifier: "welcomeWhatThisIs"
            ) {
                Text(
                    """
                    Aujour is a journal made of plain markdown files — one file \
                    a day, with today's already open and waiting. Nothing goes \
                    into your folder until you write something.
                    """
                )
                Text(
                    """
                    Nothing is locked up in the app. Every day you write is a \
                    file you can open in Files, edit in Obsidian, and still \
                    read in twenty years.
                    """
                )
            }

        case .whereYourWordsGo:
            whereYourWordsGo

        case .theDailyReminder:
            WelcomePage(
                symbol: "bell.badge",
                title: "A gentle reminder?",
                identifier: "welcomeTheDailyReminder"
            ) {
                Text(
                    """
                    One notification a day and nothing else — no badges, no \
                    streaks, and nothing at all on a day you've already \
                    written in.
                    """
                )
                // The same offer the journal sheet makes, out of the same
                // list, because it is the same setting.
                Picker("When", selection: $time) {
                    ForEach(DailyReminder.everyHalfHour, id: \.self) { time in
                        Text(time.spelledOut()).tag(time)
                    }
                }
                .pickerStyle(.menu)
                // A control, and so in the identity's chrome face and the
                // accent rather than in the prose voice and the muted ink the
                // page around it is set in: what a finger acts on is not the
                // app speaking, and a time that read as a sentence would be a
                // time nobody knew they could change.
                .lettering(.rowLabel)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("welcomeReminderTime")

                // Only after somebody has taken the offer up and the device
                // has said no, which is the one answer that leaves this page
                // still on screen: the welcome does not close over a reminder
                // it cannot deliver.
                if journal.dailyReminder.access == .refused {
                    NudgesAreTurnedOffNotice(identifier: "welcomeReminderRefused")
                }

                Aside(
                    """
                    Skip it and Aujour stays quiet. You can set one — or take \
                    it away again — whenever you like, under Settings.
                    """
                )
            }
        }
    }

    /// The page that is about this install rather than about the app: the
    /// folder Aujour found, named the way the Files app names it, and the
    /// sentence that says what being there promises.
    ///
    /// The same two lines the journal sheet shows, said here first because
    /// this is the question a markdown journal has to answer before anything
    /// else — where are my words, and what happens to them if I delete this.
    @ViewBuilder
    private var whereYourWordsGo: some View {
        switch journal.state {
        case .opening:
            WelcomePage(
                symbol: "folder",
                title: "Finding somewhere to write",
                identifier: "welcomeWhereYourWordsGo"
            ) {
                ProgressView()
                    .accessibilityIdentifier("welcomeOpeningJournal")
            }

        case .open(let root, _):
            WelcomePage(
                symbol: root.location.symbolName(onDevice: device),
                title: root.location.name(onDevice: device),
                identifier: "welcomeWhereYourWordsGo"
            ) {
                Text(root.location.promise(onDevice: device))
                Aside(
                    """
                    If you keep an Obsidian vault, you can point Aujour at a \
                    folder inside it instead — under Settings, whenever you \
                    like.
                    """
                )
            }

        case .unavailable(let problem):
            WelcomePage(
                symbol: "exclamationmark.icloud",
                title: "Where your words will go",
                identifier: "welcomeWhereYourWordsGo"
            ) {
                // Said here rather than swallowed until the welcome is over: a
                // folder that could not be opened is the one thing on this
                // page worth knowing, and the way to another one is on the
                // journal sheet a tap away.
                FolderProblemNotice(problem: problem, identifier: "welcomeFolderProblem")
            }
        }
    }

    /// Where in the three this is — a row of dots, and nothing that can be
    /// tapped: the pages are a short sentence in order, not a place to browse.
    ///
    /// The page this is drawn on in the accent, the ones it is not in the
    /// faint ink rather than in the accent thinned out. A marker is held to
    /// 3:1 (ADR 0006) and an accent at a quarter of itself clears nothing —
    /// the faint step is exactly what the identity keeps for a marker, and it
    /// is a step a reader can see.
    private var howFarThroughItThisIs: some View {
        HStack(spacing: Spacing.close) {
            ForEach(Welcome.Page.allCases) { page in
                Circle()
                    .frame(width: dotSize, height: dotSize)
                    .foregroundStyle(
                        page == welcome.page
                            ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.inkFaintColor)
                    )
            }
        }
        .accessibilityHidden(true)
        .padding(.vertical, Spacing.apart)
    }

    /// A dot grows with the system text size like everything else. It carries
    /// no words, so it does not have to — but a row of seven-point dots under
    /// lettering that has trebled is a row nobody can see any more.
    @ScaledMetric(relativeTo: .caption2) private var dotSize: CGFloat = 7

    @ViewBuilder
    private var waysOn: some View {
        VStack(spacing: Spacing.close) {
            if welcome.isOnTheLastPage {
                TheWayOn(
                    "Remind me at \(time.spelledOut())",
                    identifier: "takeTheReminderUp"
                ) {
                    end(remindingAt: time)
                }

                TheWayBack("Not now", identifier: "skipTheReminder") {
                    end(remindingAt: nil)
                }
            } else {
                TheWayOn("Continue", identifier: "continueTheWelcome") { welcome.next() }
            }

            if welcome.page != .whatThisIs {
                TheWayBack("Back", identifier: "goBackAPage") { welcome.back() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func end(remindingAt time: TimeOfDay?) {
        Task { await journal.endTheWelcome(remindingAt: time) }
    }
}

/// One page of the welcome: a mark, a line, and what there is to say under it.
///
/// The same shape three times over, so that moving through them is the words
/// changing rather than the screen being rebuilt.
private struct WelcomePage<Body: View>: View {
    let symbol: String
    let title: String

    /// What a test finds this page by — which page is on screen is the one
    /// thing about the welcome a running app has to be able to say.
    let identifier: String

    @ViewBuilder let content: Body

    /// The mark grows with the reader's text size, and stops. It is the one
    /// thing on the page carrying no words, so a first run whose whole first
    /// screenful had become an icon would have lost the sentence to keep a
    /// decoration.
    @ScaledMetric(relativeTo: .title) private var markSize: CGFloat = 54

    var body: some View {
        VStack(spacing: Spacing.apart) {
            Image(systemName: symbol)
                .font(.system(size: min(markSize, 96)))
                .foregroundStyle(.tint)
                // The line under it says what the page is. Read out, the mark
                // would be the page named twice.
                .accessibilityHidden(true)

            Text(title)
                .lettering(.proseHeading)
                .foregroundStyle(Palette.inkColor)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(identifier)

            VStack(spacing: Spacing.comfortable) {
                content
            }
            // The identity's speaking voice, which is what these three pages
            // are: the app addressing the reader in full sentences rather than
            // labelling anything. Anything on a page that is not that — a
            // control, a problem notice, a sentence turned aside — says so by
            // setting its own.
            .lettering(.pageVoice)
            .foregroundStyle(Palette.inkMutedColor)
            .multilineTextAlignment(.center)
        }
    }
}

/// The sentence a page turns aside to say: what it does not commit anybody to,
/// and where the rest of it lives.
///
/// The same voice as the page, quieter and italic, rather than a caption in
/// the system's face — on a page set in Newsreader, a system-face aside is the
/// one line that reads as having been written by somebody else.
private struct Aside: View {
    let words: String

    init(_ words: String) { self.words = words }

    var body: some View {
        Text(words)
            .lettering(.aside)
            .foregroundStyle(Palette.inkMutedColor)
    }
}

/// What a press looks like on a welcome button.
///
/// Both of them are drawn rather than handed over as a string, and a drawn
/// label is one the platform's styles stop dimming — so the dim is put back.
/// A button that did not answer the finger on it is the first thing anybody
/// touches in Aujour appearing not to work.
private struct PressedByAFinger: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The button that carries the welcome forward: the accent, filled, with the
/// one thing the identity writes on a fill of the accent (``Palette/onAccent``,
/// held to 4.5:1 against every one of the nine accents).
///
/// Drawn rather than `.borderedProminent`, which is the platform's own capsule
/// in the platform's own lettering — the one control on the first screen of
/// the app that would say it had been built out of somebody else's parts.
private struct TheWayOn: View {
    let words: String

    /// What a test presses it by. On the button itself and not on a container
    /// around it: an identifier on a wrapper is an identifier `app.buttons`
    /// cannot find.
    let identifier: String

    let act: () -> Void

    init(_ words: String, identifier: String, act: @escaping () -> Void) {
        self.words = words
        self.identifier = identifier
        self.act = act
    }

    var body: some View {
        Button(action: act) {
            Text(words)
                .lettering(.rowLabel)
                .foregroundStyle(Palette.onAccentColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.comfortable)
                .background(.tint, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressedByAFinger())
        .elevated(.resting)
        .accessibilityIdentifier(identifier)
    }
}

/// The way that is not forward: skipping the offer, or stepping back a page.
///
/// Words and no capsule. There is exactly one thing to press on each page and
/// two filled buttons would be two of them, which is the whole reason the
/// welcome can be left without anybody thinking they have broken it.
private struct TheWayBack: View {
    let words: String
    let identifier: String
    let act: () -> Void

    init(_ words: String, identifier: String, act: @escaping () -> Void) {
        self.words = words
        self.identifier = identifier
        self.act = act
    }

    var body: some View {
        Button(action: act) {
            Text(words)
                .lettering(.rowLabel)
                .foregroundStyle(Palette.inkMutedColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.comfortable)
                .contentShape(.rect)
        }
        .buttonStyle(PressedByAFinger())
        .accessibilityIdentifier(identifier)
    }
}

// Previews welcome somebody into a journal in memory, so the folder on the
// second page is the one the preview is named after rather than this Mac's.
#Preview("A fresh install") {
    WelcomeView(journal: Journal.inAPreview(over: .preview(.iCloudDrive), welcomed: false))
}

#Preview("A fresh install with iCloud Drive off") {
    WelcomeView(journal: Journal.inAPreview(over: .preview(.onThisDevice), welcomed: false))
}

#Preview("A fresh install with nowhere to write") {
    WelcomeView(journal: Journal.inAPreview(over: .preview(nil), welcomed: false))
}
