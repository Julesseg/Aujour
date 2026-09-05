import SwiftUI
import AujourCore

/// How one data placeholder writes itself out: what its lines start with, what
/// a line the day already saw through starts with, the shape its times take,
/// and what it says on a day that held nothing.
///
/// A page apiece rather than one page of everything, because the four fields
/// behind a row are one answer to one question — *what does `{{events}}` put
/// in my file?* — and two placeholders' worth of them side by side is eight
/// text fields nobody could tell apart. The rows that open these pages are on
/// the settings sheet, under "Entries", showing the token as their value: what
/// a user is looking for is "events", and what they need to see, because it is
/// the thing they type into their template, is `{{events}}`.
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
    /// until the tick is pressed. The time format is held as the pattern the
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
        Form {
            // The one thing that can stop a change here, and the reason it is
            // said on this page rather than only on the sheet behind: a folder
            // that will not take today's words takes no settings change
            // either, and the tick that did nothing is this page's.
            if let problem = journal.folderProblem {
                Section {
                    FolderProblemNotice(problem: problem, identifier: "dataPlaceholderProblem")
                }
                .settingsRows()
            }

            aWholeDay
            whatEachLineStartsWith
            if placeholder.itemsCanBeDone {
                whatADoneLineStartsWith
            }
            howTimesAreWritten
            whatADayThatHeldNothingSays
        }
        .settingsPage(titled: placeholder.onScreen)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                // One tick for all four fields — see
                // `Journal.changeHowItIsWritten`. In the bar, as the two
                // paths' are, and with a reason of this page's own: four
                // fields is a page that scrolls on a small phone, and a row
                // at the bottom of it was a button under the fold.
                Button {
                    Task { await journal.changeHowItIsWritten(placeholder, to: typed) }
                } label: {
                    Label("Change", systemImage: "checkmark")
                }
                .disabled(!isAChange)
                .accessibilityIdentifier("changeHowItIsWritten")
            }
        }
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
        Section("A day would read") {
            Text(written(example.throughTheDay))
                .font(.callout.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier("wholeDayExample")
        }
        .settingsRows()
    }

    private var whatEachLineStartsWith: some View {
        FormatField(
            title: "What each line starts with",
            prompt: "Line marker",
            text: $linePrefix,
            saying: .example(written([example.atAnHour])),
            identifier: "linePrefix"
        )
    }

    private var whatADoneLineStartsWith: some View {
        FormatField(
            title: "What something you'd already done starts with",
            prompt: "Done marker",
            text: $donePrefix,
            saying: .example(example.alreadyDone.map { written([$0]) } ?? ""),
            identifier: "donePrefix"
        )
    }

    private var howTimesAreWritten: some View {
        FormatField(
            title: "How times are written",
            prompt: "Time format",
            text: $timeFormat,
            saying: .example(written([example.atAnHour, example.withoutAnHour])),
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
            identifier: "whenEmpty"
        )
    }
}

extension DataPlaceholder {
    /// What the row and the page it opens are called — the plainest word for
    /// the thing this reads, which for both of these is the glossary's own
    /// (`CONTEXT.md`'s preamble allows that where it is also the plainest).
    var onScreen: String {
        switch self {
        case .events: "Events"
        case .reminders: "Reminders"
        }
    }

    /// The placeholder as it is written in a template, which is the one piece
    /// of jargon this screen has to show: it is the thing the user types.
    var token: String { "{{\(rawValue)}}" }
}

#Preview {
    NavigationStack {
        HowADataPlaceholderIsWrittenView(
            journal: Journal.inAPreview(over: .system),
            placeholder: .reminders
        )
    }
}
