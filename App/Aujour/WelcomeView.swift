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
                                .padding(.horizontal, 28)
                                .padding(.vertical, 24)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: room.size.height)
                    }
                }
                howFarThroughItThisIs
                waysOn
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }
            // A bare bar with one button in it: there is no title here, and a
            // large one's empty room would push three short pages down the
            // screen for nothing.
            .navigationBarTitleDisplayMode(.inline)
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
                .accessibilityIdentifier("welcomeReminderTime")

                // Only after somebody has taken the offer up and the device
                // has said no, which is the one answer that leaves this page
                // still on screen: the welcome does not close over a reminder
                // it cannot deliver.
                if journal.dailyReminder.access == .refused {
                    NudgesAreTurnedOffNotice(identifier: "welcomeReminderRefused")
                }

                Text(
                    """
                    Skip it and Aujour stays quiet. You can set one — or take \
                    it away again — whenever you like, under Your journal.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Text(
                    """
                    If you keep an Obsidian vault, you can point Aujour at a \
                    folder inside it instead — under Your journal, whenever \
                    you like.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
    private var howFarThroughItThisIs: some View {
        HStack(spacing: 7) {
            ForEach(Welcome.Page.allCases) { page in
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(.tint)
                    // Faded rather than absent for the pages this is not: how
                    // many there are is half of what a row of dots says.
                    .opacity(page == welcome.page ? 1 : 0.25)
            }
        }
        .accessibilityHidden(true)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var waysOn: some View {
        VStack(spacing: 10) {
            if welcome.isOnTheLastPage {
                Button("Remind me at \(time.spelledOut())") {
                    end(remindingAt: time)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("takeTheReminderUp")

                Button("Not now") { end(remindingAt: nil) }
                    .accessibilityIdentifier("skipTheReminder")
            } else {
                Button("Continue") { welcome.next() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("continueTheWelcome")
            }

            if welcome.page != .whatThisIs {
                Button("Back") { welcome.back() }
                    .accessibilityIdentifier("goBackAPage")
            }
        }
        .controlSize(.large)
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

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 54))
                .foregroundStyle(.tint)

            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(identifier)

            VStack(spacing: 14) {
                content
            }
            .font(.callout)
            .multilineTextAlignment(.center)
        }
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
