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

            Text(
                """
                Put these in your template and Aujour fills them in when the \
                day is spawned — as plain markdown, so the file reads the same \
                in Obsidian and nothing has to be worked out again to read it.
                """
            )
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
/// Every field is a format string nobody can evaluate in their head, which is
/// the same problem the Path Template has and is solved here the same way: the
/// line it would write, underneath it, changing as it is typed. The example
/// day is invented rather than read off the user's calendar — a real day may
/// hold nothing, and a preview that changed as the afternoon went on would be
/// one nobody could check a typed character against.
///
/// The done marker is only asked about where a day can have seen something
/// through. An event is a thing that happens rather than a thing to do, so a
/// marker for it would be a field that could never change a single line.
///
/// One button for all four fields. They are one answer, and saving them one at
/// a time would reopen the journal four times over a single edit.
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
        _donePrefix = State(initialValue: inForce.donePrefix)
        _timeFormat = State(initialValue: inForce.timeFormat?.pattern ?? "")
        _whenEmpty = State(initialValue: inForce.whenEmpty)
    }

    /// What is being typed, as the format it would be — which is what every
    /// example on the page is rendered through.
    private var typed: DataPlaceholderFormat {
        DataPlaceholderFormat(
            linePrefix: linePrefix,
            // A placeholder whose items never get done has no marker of its
            // own to keep: it takes the line prefix, which is what leaves its
            // lines reading the same either way.
            donePrefix: placeholder.itemsCanBeDone ? donePrefix : nil,
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
            VStack(alignment: .leading, spacing: 20) {
                aWholeDay
                Divider()
                whatEachLineStartsWith
                if placeholder.itemsCanBeDone {
                    Divider()
                    whatADoneLineStartsWith
                }
                Divider()
                howTimesAreWritten
                Divider()
                whatADayThatHeldNothingSays
                Button("Change") {
                    Task { await journal.changeHowItIsWritten(placeholder, to: typed) }
                }
                .buttonStyle(.bordered)
                .disabled(!isAChange)
                .accessibilityIdentifier("changeHowItIsWritten")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
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
        field(
            titled: "What each line starts with",
            text: $linePrefix,
            prompt: "Line marker",
            identifier: "linePrefix",
            example: written([example.atAnHour]),
            saying: """
                A markdown list marker keeps this part of the day a list in \
                Aujour and a list in Obsidian. Leave it empty for plain lines.
                """
        )
    }

    private var whatADoneLineStartsWith: some View {
        field(
            titled: "What something you'd already done starts with",
            text: $donePrefix,
            prompt: "Done marker",
            identifier: "donePrefix",
            example: example.alreadyDone.map { written([$0]) } ?? "",
            saying: """
                A day written up later held everything that day's list held, \
                and what got done is written as done rather than as still to \
                do — a ticked box says so, and so does anything else you put \
                here.
                """
        )
    }

    private var howTimesAreWritten: some View {
        field(
            titled: "How times are written",
            text: $timeFormat,
            prompt: "Time format",
            identifier: "timeFormat",
            example: written([example.atAnHour, example.withoutAnHour]),
            saying: """
                The same date tokens as your entry path — HH:mm for a 24-hour \
                clock, h:mm a for a 12-hour one. Leave it empty to write no \
                times at all. Anything the day held without an hour is written \
                without one either way.
                """
        )
    }

    private var whatADayThatHeldNothingSays: some View {
        field(
            titled: "What a day that held nothing says",
            text: $whenEmpty,
            prompt: "On an empty day",
            identifier: "whenEmpty",
            // Said in words rather than shown as the nothing it is: an example
            // line that is blank looks like an example that failed to render.
            example: whenEmpty.isEmpty ? "Nothing at all — the day is left blank there." : whenEmpty,
            saying: """
                Empty leaves no trace of the placeholder having been asked, so \
                a heading with nothing under it stays a heading with nothing \
                under it.
                """
        )
    }

    /// One field of the format: what it is called, what is in it, the line it
    /// would write, and the one thing worth saying about it.
    ///
    /// The same shape the entry path and the photo folder already have —
    /// typed above, worked example below, prose under that — because it is
    /// the same problem: a format string is easier to check against one real
    /// line than to read.
    private func field(
        titled title: String,
        text: Binding<String>,
        prompt: String,
        identifier: String,
        example: String,
        saying: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .accessibilityIdentifier("\(identifier)Field")

            Text(example)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(identifier)Example")

            Text(saying)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
