import SwiftUI
import AujourCore

/// The offer a Path Template change comes with, and then what came of it:
/// move the entries already in the folder into the new shape, or leave them
/// where they are (ADR 0002).
///
/// Three states, because a migration is three moments and only one of them is
/// a decision. It says what it would do before it does any of it; it says how
/// far through it is while it is doing it, because it touches every file in
/// somebody's journal and that can run long enough that a spinner would be a
/// lie; and it says what became of every day afterwards, which is rarely all
/// one thing.
///
/// **Nothing here is drawn as a failure.** Not a day parked beside a file that
/// was already in the vault, not a day the folder would not move, and not the
/// user deciding to leave the whole journal where it is. There is no error
/// colour in the palette to reach for, which is how the identity says the
/// same thing (`v1-decisions.md`; ADR 0006).
struct PathTemplateMigrationSheet: View {
    let journal: Journal

    /// The one colour the app spends on itself, and so the one this screen is
    /// tinted with — the reader's own choice, not a colour picked here to mean
    /// something.
    let accent: Accent

    let template: PathTemplate
    let plan: MigrationPlan

    @State private var stage: Stage = .offering
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        /// Waiting on the user, which is the whole point of the screen.
        case offering
        /// The files are moving, and this is how far through.
        case moving(MigrationProgress)
        /// What became of them.
        case moved(MigrationOutcome)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.apart) {
                    switch stage {
                    case .offering:
                        MigrationOffer(
                            plan: plan,
                            accent: accent,
                            move: move,
                            leaveThem: leaveThemWhereTheyAre
                        )
                    case .moving(let progress):
                        MigrationUnderway(progress: progress, accent: accent)
                    case .moved(let outcome):
                        MigrationReport(outcome: outcome, accent: accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.apart)
            }
            .background(Palette.sheetColor)
            .navigationTitle("Where your entries go")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isBusy)
        }
        .tint(accent.ink)
    }

    private var isBusy: Bool {
        if case .moving = stage { true } else { false }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch stage {
        case .offering:
            // Backing out leaves the template alone as well as the files:
            // nothing about this change has happened yet.
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("cancelEntryPathChange")
            }
        case .moving:
            // Nothing to press while the files are moving. Stopping halfway
            // is not an outcome worth offering — every move already made is
            // one the plan says is safe, and the way out of a migration that
            // did not finish is to change the entry path again.
            ToolbarItem(placement: .cancellationAction) { EmptyView() }
        case .moved:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("dismissMigrationSummary")
            }
        }
    }

    // MARK: - Deciding

    private func move() {
        // Nought out of the total rather than nothing at all: the bar is
        // there from the first frame, so what the user watches is one bar
        // filling and not a blank pause followed by one.
        stage = .moving(MigrationProgress(settled: 0, total: plan.entryCount))
        Task {
            let outcome = await journal.changeThePathTemplate(
                to: template,
                movingEntriesBy: plan,
                reporting: { stage = .moving($0) }
            )
            stage = .moved(outcome ?? MigrationOutcome(moved: [], parked: [], leftBehind: []))
        }
    }

    /// The skip. The template changes and the files do not — which leaves the
    /// old ones on disk, no longer Entries and no longer surfaced anywhere.
    /// Aujour keeps no list of them: they are the user's to manage in Files or
    /// in Obsidian (ADR 0002).
    ///
    /// Straight out afterwards, with nothing reported. There is nothing to
    /// report: every file is where it was, which is what was asked for.
    private func leaveThemWhereTheyAre() {
        Task {
            await journal.changeThePathTemplate(to: template, movingEntriesBy: nil)
            dismiss()
        }
    }
}

// MARK: - Before anything moves

/// What the change would do to the folder, said before a single file is
/// touched.
///
/// Everything on it is about files, because that is what the user is deciding
/// about — how many move, which days already have something at the path they
/// would move to, and what happens to what is not moved. Nothing here is
/// reversible by Aujour afterwards, so all of it is said in advance rather
/// than reported after.
struct MigrationOffer: View {
    let plan: MigrationPlan
    let accent: Accent

    let move: () -> Void
    let leaveThem: () -> Void

    // MARK: - What it says

    /// The whole decision in one line, and a count in prose rather than a
    /// bare number: what the user is agreeing to is a number of their own
    /// days, and "3" would be asking them to work out what of theirs it was
    /// about.
    var question: String { "Move your \(counted(plan.entryCount, "entry", "entries"))?" }

    /// What either answer comes to. Both halves matter — that the app stops
    /// showing what it does not move, and that the files are in the folder
    /// whichever way this goes.
    static let consequence = """
        Your entries are only entries where your entry path says they are, so anything \
        Aujour doesn't move stops showing up in the app. The files stay in your folder \
        either way — nothing is deleted.
        """

    /// The one consequence nobody would guess, and the reason ADR 0002 says
    /// the prompt has to mention it: a daily note that changes name is a note
    /// the vault's own links no longer reach.
    static let linkWarning = "Renaming files can break [[links]] to your daily notes in Obsidian."

    /// The days whose new path something is already at.
    ///
    /// Named here one by one rather than asked about one at a time as the
    /// files move: a vault that already keeps daily notes where the new
    /// template puts them collides on every single day, and a hundred prompts
    /// is not a decision anybody makes — it is one they dismiss.
    var colliding: [MigrationPlan.Move] { plan.collisions }

    /// How many of them there are, or nothing at all where there are none —
    /// a heading over an empty list is a worry with nothing to act on.
    var collisionHeading: String? {
        switch colliding.count {
        case 0: nil
        case 1: "1 day already has a file where it would go"
        case let many: "\(many) days already have a file where they would go"
        }
    }

    /// And what will become of each — the whole of ADR 0002's collision rule,
    /// said once over the list rather than repeated down it.
    static let collisionExplanation = """
        Aujour never overwrites. The file that's already there stays as that day's entry, \
        and yours is kept beside it — open both and merge them by hand.
        """

    /// The two ways out, both of which are the user's to take.
    static let moveAction = "Move Them"
    static let leaveAction = "Leave Them Where They Are"

    // MARK: - What it is drawn in

    var mark: UIColor { accent.uiColor }
    var questionInk: UIColor { Palette.ink }

    /// What the collisions are listed in. The prose either side of them is a
    /// `Note`, which carries the same muted ink by construction.
    var detailInk: UIColor { Palette.inkMuted }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.apart) {
            HStack(alignment: .top, spacing: Spacing.comfortable) {
                AccentMark(mark)
                VStack(alignment: .leading, spacing: Spacing.close) {
                    Text(question)
                        .lettering(.sheetTitle)
                        .foregroundStyle(Color(questionInk))
                        .accessibilityIdentifier("migrationPrompt")
                    Note(Self.consequence)
                    Note(Self.linkWarning)
                        .accessibilityIdentifier("migrationLinkWarning")
                }
            }

            collisions

            VStack(spacing: Spacing.comfortable) {
                MigrationAction(
                    words: Self.moveAction,
                    accent: accent,
                    identifier: "moveEntries",
                    act: move
                )
                MigrationAction(
                    words: Self.leaveAction,
                    accent: accent,
                    identifier: "skipMigration",
                    act: leaveThem
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var collisions: some View {
        if let collisionHeading {
            VStack(alignment: .leading, spacing: Spacing.close) {
                Text(collisionHeading)
                    .lettering(.rowValue)
                    .foregroundStyle(Color(questionInk))
                    .accessibilityIdentifier("migrationCollisions")

                Note(Self.collisionExplanation)

                VStack(alignment: .leading, spacing: Spacing.tight) {
                    ForEach(colliding, id: \.to) { collision in
                        // The day, and the name the file of it would be kept
                        // under — which is the name they will go looking for
                        // in Obsidian or in Files.
                        Text("\(collision.day.description) → \(collision.name)")
                            .lettering(.note)
                            .foregroundStyle(Color(detailInk))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onACard()
        }
    }
}

/// A way out of the offer.
///
/// One treatment, drawn twice, and that is the point: moving the entries and
/// leaving them where they are are both the user's to choose, so there is no
/// second style on this screen for either of them to be demoted into. A filled
/// button beside an outlined one would have picked the answer already, and a
/// skipped migration is a legitimate choice rather than a mistake somebody is
/// being talked out of (ADR 0002).
struct MigrationAction: View {
    let words: String
    let accent: Accent

    /// What a test finds this one by — the screen offers two of these and the
    /// whole point is that nothing else tells them apart.
    let identifier: String

    let act: () -> Void

    /// A word on a wash of the accent takes its ink shade and a shape takes
    /// the accent itself — the one rule the palette rests on
    /// (`Accent.inkColor`).
    var ink: UIColor { accent.inkColor }
    var ring: UIColor { accent.uiColor }
    var wash: UIColor { accent.softColor }

    var body: some View {
        Button(action: act) {
            Text(words)
                .lettering(.rowLabel)
                .foregroundStyle(Color(ink))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.comfortable)
                .background(Color(wash), in: Capsule())
                .overlay(Capsule().stroke(Color(ring), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - While it moves

/// How far through the migration is.
///
/// Determinate, and that is the whole of this state: it moves every file in
/// somebody's journal, one at a time through a folder that may be waiting on
/// iCloud for each of them, and a journal is as big as a journal gets. A
/// spinner over that says only that the app has not crashed.
///
/// A number beside the bar as well, because a bar on its own cannot be
/// checked: a reader watching one has no way to tell a slow migration from a
/// stuck one.
struct MigrationUnderway: View {
    let progress: MigrationProgress
    let accent: Accent

    static let headline = "Moving your entries"

    /// How full the bar is, from nought to one.
    var fraction: Double { progress.fraction }

    /// The same thing in figures. Days and not moves, so it is the number the
    /// offer was made in: a day that had to step aside on the way is still one
    /// entry, and a tally that ran past the count somebody agreed to would be
    /// about a different journal.
    var tally: String {
        "\(progress.settled) of \(counted(progress.total, "entry", "entries"))"
    }

    var headlineInk: UIColor { Palette.ink }
    var tallyInk: UIColor { Palette.inkMuted }
    var barInk: UIColor { accent.uiColor }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.close) {
            Text(Self.headline)
                .lettering(.sheetTitle)
                .foregroundStyle(Color(headlineInk))
                .accessibilityIdentifier("migrationUnderway")

            ProgressView(value: fraction)
                .tint(Color(barInk))
                .accessibilityLabel(Self.headline)
                .accessibilityValue(tally)

            Text(tally)
                .lettering(.note)
                .foregroundStyle(Color(tallyInk))
                .monospacedDigit()
                .accessibilityIdentifier("migrationProgress")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - What became of them

/// What the migration did, in the inline banner's shape and in the accent
/// (`v1-decisions.md`).
///
/// Its shape and not its ground: the banner over a day is drawn in the
/// system's glass because it floats over words somebody is scrolling, and
/// this is a card on a sheet with nothing moving behind it. What carries over
/// is the arrangement — the accent's mark, then the news, then what it means
/// — and the promise that arrangement makes.
///
/// Three things and not one, because a migration is rarely all of one thing:
/// the days that moved, the days kept beside a file that already claimed them,
/// and the days the folder would not move. Every day the plan was about is in
/// exactly one of them.
///
/// **Never an error colour**, on any of the three. A parked file is not a
/// loss — both versions are somebody's words and both are still in the folder
/// — and a day left behind is a file exactly where it was, which is a thing to
/// try again rather than a thing that went wrong.
struct MigrationReport: View {
    let outcome: MigrationOutcome
    let accent: Accent

    // MARK: - What it says

    /// The one line at the top: how much of the journal moved.
    ///
    /// Counted over the days that were parked as well as the days that took
    /// their new path, because both of them moved — a day whose new path was
    /// taken is at a name beside it, and the sentence underneath is what says
    /// which. "0 entries moved" over a folder where a file did move is the one
    /// thing this must not say.
    var headline: String {
        let moved = outcome.moved.count + outcome.parked.count
        guard moved > 0 else { return "Nothing moved." }
        return "\(counted(moved, "entry", "entries")) moved."
    }

    /// Where the days whose new path was taken were kept, by name — which is
    /// what the user will see the file called when they go looking for it.
    var parkedFiles: String? {
        guard !outcome.parked.isEmpty else { return nil }
        return """
            \(counted(outcome.parked.count, "day", "days")) already had a file where \
            \(outcome.parked.count == 1 ? "it" : "they") would go, so both were kept: \
            \(named(outcome.parked.map(\.name))). Open them in Files or Obsidian to bring \
            across anything you want.
            """
    }

    /// The days the folder would not move, named — a day is what the user can
    /// go and look at, and a bare count would leave them hunting for which.
    var leftBehind: String? {
        guard !outcome.leftBehind.isEmpty else { return nil }
        let days = named(outcome.leftBehind.map(\.day.description))
        return outcome.leftBehind.count == 1
            ? """
            \(days) couldn't be moved and is still where it was. Nothing was lost — change \
            your entry path again to try it once more.
            """
            : """
            \(days) couldn't be moved and are still where they were. Nothing was lost — \
            change your entry path again to try them once more.
            """
    }

    // MARK: - What it is drawn in

    var mark: UIColor { accent.uiColor }
    var headlineInk: UIColor { Palette.ink }
    var detailInk: UIColor { Palette.inkMuted }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.comfortable) {
            AccentMark(mark)
            VStack(alignment: .leading, spacing: Spacing.close) {
                Text(headline)
                    .lettering(.sheetTitle)
                    .foregroundStyle(Color(headlineInk))
                    .accessibilityIdentifier("migrationSummary")

                if let parkedFiles {
                    Text(parkedFiles)
                        .lettering(.note)
                        .foregroundStyle(Color(detailInk))
                        .accessibilityIdentifier("migrationParkedFiles")
                }

                if let leftBehind {
                    Text(leftBehind)
                        .lettering(.note)
                        .foregroundStyle(Color(detailInk))
                        .accessibilityIdentifier("migrationLeftBehind")
                }
            }
            Spacer(minLength: 0)
        }
        .onACard()
    }
}

/// A number and the noun it counts, in the form the sentence needs — "1
/// entry", "12 entries".
///
/// Every sentence on this screen is about a count of the user's own days, and
/// a screen that says "1 entries" about somebody's journal reads as a screen
/// that was not looked at.
private func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}

/// The dot a notice opens with: the reader's accent, said as a shape.
///
/// Grown against the heading it sits beside, and dropped far enough down to
/// sit on that heading's own line — a seven-point dot beside a line of
/// accessibility-sized text would be a speck, and one pinned to the top of
/// the stack would float above the words it belongs to.
private struct AccentMark: View {
    let colour: UIColor

    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 7
    @ScaledMetric(relativeTo: .title2) private var drop: CGFloat = 9

    init(_ colour: UIColor) { self.colour = colour }

    var body: some View {
        Circle()
            .fill(Color(colour))
            .frame(width: size, height: size)
            .padding(.top, drop)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Puts this on a card: the identity's raised surface, with the hairline
    /// that gives it an edge where the paper behind it is nearly the same
    /// colour.
    fileprivate func onACard() -> some View {
        padding(Spacing.comfortable)
            .background(Palette.cardColor, in: .rect(cornerRadius: Rounding.card))
            .overlay(
                RoundedRectangle(cornerRadius: Rounding.card)
                    .stroke(Palette.ruleColor, lineWidth: 1)
            )
    }
}

/// The first few of them by name, and a count for the rest.
///
/// Named rather than only counted, because a name is what somebody can go and
/// look at. Only the first few, because a vault that already keeps its daily
/// notes where the new entry path puts them collides on every single day, and
/// four hundred file names run together in one sentence is a sentence nobody
/// reads — the count at the end is what says none of them were hidden.
private func named(_ names: [String], atMost few: Int = 5) -> String {
    guard names.count > few else { return names.formatted(.list(type: .and)) }
    return names.prefix(few).joined(separator: ", ") + " and \(names.count - few) more"
}
