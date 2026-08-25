import SwiftUI
import UniformTypeIdentifiers
import AujourCore

/// The journal, as something the user can see and change: the folder it lives
/// in, and every setting that shapes what goes into it.
///
/// One page and not two. The folder, the entry path, the template a day starts
/// from, when the day turns, where photos go and how they are written are six
/// answers to one question — *what is my journal, and what will Aujour do with
/// it?* — and a user who has just seen where their files are is one line away
/// from what those files will be called.
///
/// It takes the whole Journal rather than the folder it is currently over,
/// because choosing a folder closes one journal and opens another: the sheet
/// has to still be there, and still be saying something true, while that
/// happens.
///
/// Every journal-shaping setting here travels: changed on this device they
/// arrive on the iPad, changed there they arrive here while the sheet is up
/// (ADR 0003). So nothing holds its own copy of a setting for longer than it
/// is being typed, and the controls that are not text follow the journal
/// directly.
///
/// The daily reminder is the exception, and sits last under a line of its own
/// saying so. It is about the journal — it exists to ask whether today has
/// been written — but it is a property of the device that buzzes rather than
/// of the folder, so it stays here (ADR 0003). One page still: a second sheet
/// would mean a user looking for "when does Aujour nag me" had to guess which
/// of two screens the answer was on.
struct JournalSettingsSheet: View {
    let journal: Journal

    /// Whether the Files picker is up.
    @State private var picking = false

    @Environment(\.dismiss) private var dismiss

    /// "iPhone" or "iPad" — the app runs on both, and the Files app names the
    /// on-device folder after whichever one this is.
    private var device: String { UIDevice.current.model }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Scrolled, so that the two buttons stay where they are and
                // reachable however long the folder's path runs — a sheet that
                // has pushed its own actions off the bottom is a folder the
                // user cannot change.
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        whereTheJournalIs
                            .frame(maxWidth: .infinity)
                        if let problem = journal.folderProblem {
                            FolderProblemNotice(problem: problem, identifier: "folderProblem")
                        }
                        // Every section below is on screen whatever state the
                        // journal is in, and not only while it is open:
                        // changing any of these reopens the journal, and a
                        // section that came and went with that would vanish
                        // under the finger that changed it. What a journal
                        // that is not open cannot do is *carry out* a change,
                        // which is each button's own business.
                        //
                        // In the order somebody asks them in: where the files
                        // are, what they are called, what is in one when it
                        // starts, which day it is, and then the photographs.
                        Divider()
                        EntryPathSection(journal: journal)
                        Divider()
                        ContentTemplateSection(journal: journal)
                        Divider()
                        RolloverHourSection(journal: journal)
                        Divider()
                        AttachmentPathSection(journal: journal)
                        Divider()
                        EmbedSyntaxSection(journal: journal)
                        Divider()
                        DailyReminderSection(journal: journal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                waysToPointItSomewhereElse
            }
            .padding()
            .navigationTitle("Your journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Full height rather than half: this is the folder, its paths and its
        // templates, and nearly all of it would be below the fold.
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var whereTheJournalIs: some View {
        switch journal.state {
        case .opening:
            ProgressView("Opening your journal")

        case .open(let root, let entryCount):
            Image(systemName: root.location.symbolName(onDevice: device))
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text(root.location.name(onDevice: device))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("journalRootLocation")

            Text(root.location.promise(onDevice: device))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let entryCount {
                Text(entryCount == 1 ? "1 entry" : "\(entryCount) entries")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("journalEntryCount")
            }

            Text(root.url.path(percentEncoded: false))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .accessibilityIdentifier("journalRootPath")

        case .unavailable(let problem):
            // The same two sentences the screen behind is showing. Said here
            // too, because this is where the folder can be changed, and a
            // folder that cannot be reached is the likeliest reason to.
            FolderProblemNotice(problem: problem, identifier: "journalRootProblem")
        }
    }

    private var waysToPointItSomewhereElse: some View {
        VStack(spacing: 12) {
            Button("Use a custom folder…", systemImage: "folder.badge.plus") {
                chooseAFolder()
            }
            .accessibilityIdentifier("chooseCustomFolder")

            if journal.hasACustomFolder {
                Button("Use Aujour's own folder", systemImage: "arrow.uturn.backward") {
                    Task { await journal.useAujoursOwnFolder() }
                }
                .accessibilityIdentifier("useAujoursOwnFolder")
            }
        }
        .buttonStyle(.bordered)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            // Only a folder that was picked is news: the other outcome is
            // mostly the user tapping Cancel, and an error notice for a mind
            // changed is worse than nothing.
            guard case .success(let folder) = result else { return }
            Task { await journal.use(folder) }
        }
    }

    private func chooseAFolder() {
        // The Files picker is another process's screen, and driving it is the
        // one part of choosing a folder that a UI test cannot do without
        // becoming a test of that screen. So the UI suite says which folder it
        // means at launch, and it goes in through the same door the picker's
        // would — everything after this point is the app's own code.
        if let folder = UITestingJournal.folderToPick() {
            Task { await journal.use(folder) }
            return
        }
        picking = true
    }
}

/// The file a day nobody has written yet is spawned from.
///
/// A file the user points at with the system's picker rather than a page they
/// type into, because that is what a Content Template is: a markdown file they
/// keep and edit, which Obsidian's daily notes name the same way and which
/// they very likely already have. It can be anywhere they keep their writing —
/// beside their entries, in a vault's `Templates` folder, in iCloud Drive —
/// and Aujour reads it where it lies, every time a day is spawned. There is no
/// copy here to go stale (ADR 0005).
private struct ContentTemplateSection: View {
    let journal: Journal

    /// Whether the Files picker is up.
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What a new day starts from")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                chooseAFile()
            } label: {
                HStack {
                    Text(journal.contentTemplateName ?? "Choose a template file…")
                        .font(.callout.monospaced())
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("contentTemplateFile")

            if journal.theTemplateIsOutOfReach {
                // The one thing about this setting worth saying out loud: a
                // template that is set and unreachable is a blank page nobody
                // asked for.
                Text(
                    """
                    Aujour can't reach the template file you chose — it may \
                    have been renamed, moved, or not come down from iCloud \
                    yet. New days start blank until it's back.
                    """
                )
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("contentTemplateOutOfReach")
            }

            if journal.contentTemplateName != nil || journal.theTemplateIsOutOfReach {
                Button("Use no template", systemImage: "xmark") {
                    Task { await journal.useAsTheContentTemplate(nil) }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .accessibilityIdentifier("noContentTemplate")
            }

            Text(
                """
                Days you haven't written yet start from this file, read afresh \
                each time — edit it in Obsidian and tomorrow's entry follows. \
                {{date}}, {{time}} and {{title}} are filled in when the day is \
                spawned; anything Aujour doesn't know stays as you wrote it. \
                Keep it inside your journal folder and your other devices find \
                it too; anywhere else, point each device at it once.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.markdownFiles) { result in
            // Only a file that was picked is news: the other outcome is mostly
            // the user tapping Cancel, and a notice for a mind changed is
            // worse than nothing.
            guard case .success(let file) = result else { return }
            Task { await journal.useAsTheContentTemplate(file) }
        }
    }

    /// What the picker will let them choose: markdown, and the plain text it
    /// is a kind of — a template written in a plain `.txt` is still a
    /// template, and a picker that greyed it out would be lying about why.
    private static let markdownFiles: [UTType] = [
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        .plainText,
        .text,
    ]

    private func chooseAFile() {
        // The Files picker is another process's screen, and driving it is the
        // one part of choosing a file that a UI test cannot do without
        // becoming a test of that screen. So the UI suite says which file it
        // means at launch, and it goes in through the same door the picker's
        // would — everything after this point is the app's own code.
        if let file = UITestingJournal.templateToPick() {
            Task { await journal.useAsTheContentTemplate(file) }
            return
        }
        picking = true
    }
}

/// When the current Journal Day advances.
///
/// The setting shown as the day it makes it right now, and not only as an
/// hour: "the day turns at 4 AM" is a rule somebody has to apply to their own
/// clock, and "right now this is Tuesday" is the answer they were applying it
/// for.
private struct RolloverHourSection: View {
    let journal: Journal

    /// The setting, and changing it — a binding rather than local state,
    /// because a Rollover Hour set on the iPad arrives here while the sheet
    /// is up (ADR 0003).
    private var hour: Binding<Int> {
        Binding(
            get: { journal.rolloverHour.hour },
            set: { chosen in
                guard let hour = RolloverHour(hour: chosen) else { return }
                Task { await journal.changeTheRolloverHour(to: hour) }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When the day turns")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("When the day turns", selection: hour) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(Self.onTheClock(hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("rolloverHour")

            Text("Right now, you're writing \(journal.dayOnScreen.spelledOut()).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("rolloverHourDay")

            Text(
                """
                Entries already written stay on the days they're named for. \
                Push this later than midnight and a late night lands on the \
                day you're describing rather than the one the clock has \
                moved on to.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// An hour of the day as this user's clock writes it — 12- or 24-hour,
    /// whichever their region is on.
    private static func onTheClock(_ hour: Int) -> String {
        let midnight = Calendar.current.startOfDay(for: Date())
        let atThatHour =
            Calendar.current.date(byAdding: .hour, value: hour, to: midnight) ?? midnight
        return atThatHour.formatted(date: .omitted, time: .shortened)
    }
}

/// Where a day's photographs go inside the journal folder — the Attachment
/// Path Template, as something the user can change.
///
/// The same field as the entry path, and deliberately not the same ceremony:
/// changing where photographs go moves nothing. The pictures already in the
/// folder are pointed at by the days that embed them, and a picture that
/// moved would leave the day naming a file that is not there — so this
/// decides where the next one lands and nothing else.
private struct AttachmentPathSection: View {
    let journal: Journal

    @State private var typed: String

    init(journal: Journal) {
        self.journal = journal
        _typed = State(initialValue: journal.attachmentPathTemplate)
    }

    /// The typed template, read — or the sentence saying why it cannot be.
    /// `AttachmentPathTemplate` throws its rejection and nothing else, so this
    /// is the sentence to show rather than a guess at one.
    private var typedTemplate: Result<AttachmentPathTemplate, PathTemplateError> {
        do {
            return .success(try AttachmentPathTemplate(typed))
        } catch {
            return .failure(error)
        }
    }

    private var rejection: PathTemplateError? {
        if case .failure(let rejection) = typedTemplate { rejection } else { nil }
    }

    private var isAChange: Bool { typed != journal.attachmentPathTemplate }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where photos go")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Photo folder", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .accessibilityIdentifier("attachmentPathField")

            saying

            Text(
                """
                Inside your journal folder. Date tokens like YYYY and MM are \
                filled in; anything in [brackets] is a folder name. Photos \
                already in the journal stay where they are.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Change") {
                guard case .success(let template) = typedTemplate else { return }
                Task { await journal.changeTheAttachmentPathTemplate(to: template) }
            }
            .buttonStyle(.bordered)
            .disabled(!isAChange || rejection != nil)
            .accessibilityIdentifier("changeAttachmentPath")
        }
        .onChange(of: journal.attachmentPathTemplate) { _, inForce in typed = inForce }
    }

    /// The one line under the field: the folder today's photograph would go
    /// into, or why the template cannot say.
    @ViewBuilder
    private var saying: some View {
        if let rejection {
            Text(rejection.description)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("attachmentPathProblem")
        } else if case .success(let template) = typedTemplate {
            // The template made concrete on the day the user is in, the way
            // the entry path and the embed are: a folder described in tokens
            // is a folder somebody has to imagine.
            Text(template.render(journal.dayOnScreen))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("attachmentPathExample")
        }
    }
}

/// One gentle nudge a day, at a time the user chooses — the last section, and
/// the only one on this sheet that stays on the device that set it (ADR 0003).
///
/// Off until a time is chosen, which is the whole of what the toggle means:
/// there is no reminder to disable on a fresh install, because Aujour has
/// never nudged anybody who did not ask it to. Turning it on is also the one
/// moment the notification permission is asked for — the app has no other
/// reason to want one.
///
/// The time is a menu of half hours rather than a clock face to spin. It is
/// the same control the Rollover Hour uses, it is one tap and a scroll rather
/// than two wheels, and nobody has ever wanted to be reminded at 9:07.
private struct DailyReminderSection: View {
    let journal: Journal

    private var reminder: DailyReminder { journal.dailyReminder }

    /// Every half hour of the day, in order.
    private static let times: [TimeOfDay] = (0..<24).flatMap { hour in
        [0, 30].compactMap { TimeOfDay(hour: hour, minute: $0) }
    }

    /// Whether there is a reminder at all — a binding rather than local state,
    /// like every other control here, so the switch follows the setting rather
    /// than remembering its own idea of it.
    private var isOn: Binding<Bool> {
        Binding(
            get: { reminder.time != nil },
            set: { wanted in
                Task {
                    await journal.remindMeDaily(at: wanted ? DailyReminder.suggestedTime : nil)
                }
            }
        )
    }

    private var time: Binding<TimeOfDay> {
        Binding(
            get: { reminder.time ?? DailyReminder.suggestedTime },
            set: { chosen in Task { await journal.remindMeDaily(at: chosen) } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A daily reminder")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle("Remind me to write", isOn: isOn)
                .accessibilityIdentifier("dailyReminder")

            if reminder.time != nil {
                Picker("When", selection: time) {
                    ForEach(Self.times, id: \.self) { time in
                        Text(time.spelledOut()).tag(time)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("dailyReminderTime")

                whatWillHappen
            }

            Text(
                """
                One notification a day and nothing else — no badges, no \
                streaks, and nothing at all on a day you've already written \
                in. Unlike everything above, the time stays on this device: \
                your iPad keeps its own, or none.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// The one line worth saying under the time: when the next one is due, or
    /// that none of them can arrive.
    ///
    /// The refusal first, because it is the thing that makes the rest of the
    /// section untrue — a time set on a device where notifications are off is
    /// a reminder that will never come, and the way back is Settings rather
    /// than anything on this screen.
    @ViewBuilder
    private var whatWillHappen: some View {
        if reminder.access == .refused {
            Text(
                """
                Notifications are turned off for Aujour, so this won't arrive. \
                Turn them on in Settings › Notifications › Aujour.
                """
            )
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityIdentifier("dailyReminderRefused")
        } else if let next = reminder.booked.first {
            // The setting said as the thing it will actually do, the way the
            // Rollover Hour is said as the day it makes: this is where a day
            // already written shows itself, by the next reminder being about
            // tomorrow.
            Text(
                """
                Next: \(next.day.spelledOut()) at \
                \(next.at.formatted(date: .omitted, time: .shortened))
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("nextDailyReminder")
        }
    }
}

#Preview {
    JournalSettingsSheet(journal: Journal.inAPreview(over: .system))
}
