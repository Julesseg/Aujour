import SwiftUI
import AujourCore

/// The way in to how each of the day's own data writes itself into an Entry —
/// one row per data placeholder, each opening a page of its own.
///
/// A row apiece rather than one page of everything, because the four fields
/// behind a row are one answer to one question — *what does `{{events}}` put
/// in my file?* — and two placeholders' worth of them side by side is eight
/// text fields nobody could tell apart.
///
/// The token is the row's value and not its title. What a user is looking for
/// here is "my calendar"; what they need to see, because it is the thing they
/// type into their template, is `{{events}}` — so the jargon is shown rather
/// than used as a label.
///
/// These travel. What a placeholder writes is characters in the file, so an
/// iPhone and an iPad spawning one template must not write the same day two
/// ways (ADR 0003).
struct DataPlaceholderSection: View {
    let journal: Journal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What the day already knows")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(DataPlaceholder.allCases, id: \.self) { placeholder in
                NavigationLink {
                    HowADataPlaceholderIsWrittenView(journal: journal, placeholder: placeholder)
                } label: {
                    HStack {
                        Label(placeholder.inProse, systemImage: placeholder.symbolName)
                        Spacer()
                        Text(placeholder.token)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    // The whole row and not only the words on it: the middle
                    // of this one is the gap the spacer opened, and a finger
                    // landing there would be a finger landing on nothing.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dataPlaceholder-\(placeholder.rawValue)")
            }

            // One line and not the paragraph this deserves. The sheet is
            // scrolled to reach what is under it, and a caption three lines
            // long at the largest text size is most of a screen of scrolling
            // between the journal's settings and the device's — the rest of
            // what there is to say is on the page each row opens.
            Text("Put these in your template; Aujour fills them in as the day is spawned.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How one data placeholder writes itself out: what its lines start with, what
/// a line the day already saw through starts with, the shape its times take,
/// and what it says on a day that held nothing.
///
/// Every field is a `FormatField`, for the reason that type exists: these are
/// format strings nobody can evaluate in their head, and the entry path solved
/// that years of screens ago by putting the line they would write underneath
/// them. The example day is invented rather than read off the user's calendar
/// — see ``DataPlaceholder/exampleDay(on:in:)``.
///
/// The done marker is only asked about where a day can have seen something
/// through (``DataPlaceholder/itemsCanBeDone``), so `{{events}}` asks three
/// questions and `{{reminders}}` four.
struct HowADataPlaceholderIsWrittenView: View {
    let journal: Journal
    let placeholder: DataPlaceholder

    /// The four fields as they are being typed, which is not what is in force
    /// until "Change" is pressed. The time format is held as the pattern the
    /// user wrote, empty standing for no times at all — the same way an empty
    /// one is stored (`JournalSettings`).
    @State private var linePrefix: String
    @State private var donePrefix: String
    @State private var timeFormat: String
    @State private var whenEmpty: String

    init(journal: Journal, placeholder: DataPlaceholder) {
        self.journal = journal
        self.placeholder = placeholder
        let inForce = journal.howItIsWritten(placeholder)
        _linePrefix = State(initialValue: inForce.linePrefix)
        // Kept even for a placeholder that never shows the field, so that
        // changing one of the others cannot quietly rewrite a marker the user
        // was never offered.
        _donePrefix = State(initialValue: inForce.donePrefix)
        _timeFormat = State(initialValue: inForce.timeFormat?.pattern ?? "")
        _whenEmpty = State(initialValue: inForce.whenEmpty)
    }

    /// What is being typed, as the format it would be — which is what every
    /// example on the page is rendered through.
    private var typed: DataPlaceholderFormat {
        DataPlaceholderFormat(
            linePrefix: linePrefix,
            donePrefix: donePrefix,
            timeFormat: timeFormat.isEmpty ? nil : MomentFormat(timeFormat),
            whenEmpty: whenEmpty
        )
    }

    private var isAChange: Bool { typed != journal.howItIsWritten(placeholder) }

    /// The made-up day every example on this page is written from.
    private var example: DataPlaceholder.ExampleDay {
        placeholder.exampleDay(on: journal.dayOnScreen)
    }

    /// What the format being typed would write for some of that day.
    private func written(_ items: [DayItem]) -> String {
        typed.render(items, timeZone: .current, locale: .current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.apart) {
                // The one thing that can stop a change here, and the reason it
                // is said on this page rather than only on the sheet behind:
                // a folder that will not take today's words takes no settings
                // change either, and the button that did nothing is this one.
                if let problem = journal.folderProblem {
                    FolderProblemNotice(problem: problem, identifier: "dataPlaceholderProblem")
                }
                aWholeDay
                Hairline()
                whatEachLineStartsWith
                if placeholder.itemsCanBeDone {
                    Hairline()
                    whatADoneLineStartsWith
                }
                Hairline()
                howTimesAreWritten
                Hairline()
                whatADayThatHeldNothingSays
                // One button for all four fields — see
                // `Journal.changeHowItIsWritten`.
                Button("Change") {
                    Task { await journal.changeHowItIsWritten(placeholder, to: typed) }
                }
                .buttonStyle(.bordered)
                .disabled(!isAChange)
                .accessibilityIdentifier("changeHowItIsWritten")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.apart)
        }
        .navigationTitle(placeholder.inProse)
        .navigationBarTitleDisplayMode(.inline)
        // A format changed on the iPad arrives here while the page is up
        // (ADR 0003), and the fields are supposed to be showing what is in
        // force rather than their own idea of it.
        .onChange(of: journal.howItIsWritten(placeholder)) { _, inForce in
            linePrefix = inForce.linePrefix
            donePrefix = inForce.donePrefix
            timeFormat = inForce.timeFormat?.pattern ?? ""
            whenEmpty = inForce.whenEmpty
        }
    }

    /// The whole thing, before any of the fields: what a day holding one of
    /// each would come out as. The fields underneath each explain one line of
    /// it.
    private var aWholeDay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A day would read")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(written(example.throughTheDay))
                .font(.callout.monospaced())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                .textSelection(.enabled)
                .accessibilityIdentifier("wholeDayExample")

            Text("Written into the day when it's spawned, and yours to edit afterwards.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var whatEachLineStartsWith: some View {
        FormatField(
            title: "What each line starts with",
            prompt: "Line marker",
            text: $linePrefix,
            saying: .example(written([example.atAnHour])),
            guidance: """
                A markdown list marker keeps this part of the day a list in \
                Aujour and a list in Obsidian. Leave it empty for plain lines.
                """,
            identifier: "linePrefix"
        )
    }

    private var whatADoneLineStartsWith: some View {
        FormatField(
            title: "What something you'd already done starts with",
            prompt: "Done marker",
            text: $donePrefix,
            saying: .example(example.alreadyDone.map { written([$0]) } ?? ""),
            guidance: """
                A day written up later held everything that day's list held, \
                and what got done is written as done rather than as still to \
                do — a ticked box says so, and so does anything else you put \
                here.
                """,
            identifier: "donePrefix"
        )
    }

    private var howTimesAreWritten: some View {
        FormatField(
            title: "How times are written",
            prompt: "Time format",
            text: $timeFormat,
            saying: .example(written([example.atAnHour, example.withoutAnHour])),
            guidance: """
                The same date tokens as your entry path — HH:mm for a 24-hour \
                clock, h:mm a for a 12-hour one. Leave it empty to write no \
                times at all. Anything the day held without an hour is written \
                without one either way.
                """,
            identifier: "timeFormat"
        )
    }

    private var whatADayThatHeldNothingSays: some View {
        FormatField(
            title: "What a day that held nothing says",
            prompt: "On an empty day",
            text: $whenEmpty,
            // The one example said in words rather than shown as the nothing
            // it is: a blank line under a field reads as an example that
            // failed to render.
            saying: .example(
                written([]).isEmpty ? "Nothing at all — the day is left blank there." : written([])
            ),
            guidance: """
                Empty leaves no trace of the placeholder having been asked, so \
                a heading with nothing under it stays a heading with nothing \
                under it.
                """,
            identifier: "whenEmpty"
        )
    }
}

extension DataPlaceholder {
    /// What the user calls the thing this reads — the row's title, in the
    /// words somebody looking for it would use rather than the model's.
    var inProse: String {
        switch self {
        case .events: "Your calendar"
        case .reminders: "Your reminders"
        }
    }

    /// The placeholder as it is written in a template, which is the one piece
    /// of jargon this screen has to show: it is the thing the user types.
    var token: String { "{{\(rawValue)}}" }

    var symbolName: String {
        switch self {
        case .events: "calendar"
        case .reminders: "checklist"
        }
    }
}

#Preview {
    NavigationStack {
        HowADataPlaceholderIsWrittenView(
            journal: Journal.inAPreview(over: .system),
            placeholder: .reminders
        )
    }
}
