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
/// A file the user points at rather than a page they type into, because that
/// is what a Content Template is: a markdown file in their own vault, which
/// Obsidian's daily notes name the same way and which they very likely
/// already have. Aujour keeps no copy of it — editing it in Obsidian is what
/// changes tomorrow's Entry (ADR 0005).
///
/// The files offered are the ones inside the journal folder, and only those.
/// A template anywhere else on the device would be reachable through a
/// bookmark this device alone holds, and the setting travels — an iPad that
/// could not find the template would start the same day from a different page
/// (ADR 0003).
private struct ContentTemplateSection: View {
    let journal: Journal

    /// The markdown files in the folder, as of the last time it was asked —
    /// what there is to choose from, and what says whether the file in force
    /// is still there.
    @State private var markdownFiles: [String] = []

    /// Whether the list of files is up.
    @State private var choosing = false

    /// Whether the folder has been asked yet. Before it has, a template that
    /// is not in the list is not missing — it is unlooked-for, and saying
    /// "Aujour can't find this" about it would be a lie that flashes on every
    /// open.
    @State private var asked = false

    private var chosen: String { journal.contentTemplateFile }

    private var isMissing: Bool {
        asked && !chosen.isEmpty && !markdownFiles.contains(chosen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What a new day starts from")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                choosing = true
            } label: {
                HStack {
                    Text(chosen.isEmpty ? "Choose a template file…" : chosen)
                        .font(.callout.monospaced())
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("contentTemplateFile")

            if isMissing {
                Text(
                    """
                    Aujour can't find this file in your journal folder. \
                    New days start blank until it's back.
                    """
                )
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("contentTemplateMissing")
            }

            Text(
                """
                Days you haven't written yet start from this file, read afresh \
                each time — edit it in Obsidian and tomorrow's entry follows. \
                {{date}}, {{time}} and {{title}} are filled in when the day is \
                spawned; anything Aujour doesn't know stays as you wrote it. \
                It has to live inside your journal folder, so your other \
                devices can find it too.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .task(id: journal.contentTemplateFile) { await lookInTheFolder() }
        .sheet(isPresented: $choosing) {
            ContentTemplateFileList(
                files: markdownFiles,
                chosen: chosen,
                choose: { path in
                    choosing = false
                    Task { await journal.changeTheContentTemplateFile(to: path) }
                }
            )
            // Asked again on the way in: somebody who has just added a
            // template in Obsidian is exactly the person opening this.
            .task { await lookInTheFolder() }
        }
    }

    private func lookInTheFolder() async {
        markdownFiles = await journal.markdownFilesInTheFolder()
        asked = true
    }
}

/// The markdown files in the journal folder, to pick a template out of.
///
/// Every one of them, and not a guess at which are templates: an Obsidian
/// vault keeps its templates wherever its owner decided, and a list that hid
/// the file somebody was looking for would be worse than a long one. Searched
/// rather than filtered for the same reason — a vault holds thousands of
/// notes, and the way to find one among them is to type its name.
private struct ContentTemplateFileList: View {
    let files: [String]
    let chosen: String
    let choose: (String) -> Void

    @State private var searchText = ""

    @Environment(\.dismiss) private var dismiss

    private var shown: [String] {
        guard !searchText.isEmpty else { return files }
        return files.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        choose("")
                    } label: {
                        row("No template — a blank page", isChosen: chosen.isEmpty)
                    }
                    .accessibilityIdentifier("noContentTemplate")
                }

                Section {
                    if files.isEmpty {
                        Text("There are no markdown files in your journal folder yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("noMarkdownFiles")
                    }
                    ForEach(shown, id: \.self) { file in
                        Button {
                            choose(file)
                        } label: {
                            row(file, isChosen: file == chosen)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Find a file")
            .navigationTitle("Template file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ name: String, isChosen: Bool) -> some View {
        HStack {
            Text(name)
                .font(.callout.monospaced())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
            if isChosen {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier(name)
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
        let atThatHour = Calendar.current.date(byAdding: .hour, value: hour, to: midnight) ?? midnight
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

#Preview {
    JournalSettingsSheet(journal: Journal(settings: .inMemory()))
}
