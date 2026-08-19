import SwiftUI
import UniformTypeIdentifiers
import AujourCore

/// The app's one screen: today's Entry, over the folder the journal lives in.
///
/// Two things have to be true before there is anything to type into, and they
/// are the two states around the editor here — Aujour has found a folder, and
/// it has read what that folder holds for today. Neither is ever shown as an
/// empty page: an empty editor over a folder that could not be read is
/// indistinguishable from a day nobody wrote on (ADR 0001).
struct ContentView: View {
    @State private var journal: Journal
    @State private var showingJournalFolder = false
    @State private var showingJournalSettings = false
    @State private var showingCalendar = false
    @Environment(\.scenePhase) private var scenePhase

    init(journal: Journal = Journal()) {
        _journal = State(wrappedValue: journal)
    }

    /// The way out of a folder that has gone: the user's Entries are still in
    /// it, and Aujour's own folder is somewhere to write in the meantime.
    ///
    /// Offered only when the folder that failed is one they chose — for
    /// Aujour's own folder there is nowhere else to go, and a button that
    /// does nothing is worse than no button.
    private var wayBackToAujoursOwnFolder: (() async -> Void)? {
        guard journal.hasACustomFolder else { return nil }
        return { await journal.useAujoursOwnFolder() }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch journal.state {
                case .opening:
                    ProgressView("Opening your journal")
                        .accessibilityIdentifier("openingJournal")
                        .navigationTitle("Aujour")

                case .open:
                    // There is no open journal without today's Entry over it
                    // — but a blank page is the one thing this screen must
                    // never be, so the unreachable case is the spinner.
                    if let today = journal.today {
                        EntryView(editor: today)
                            .parkedFilesNotice(from: journal, for: today.day)
                            .navigationTitle(today.day.spelledOut())
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Calendar", systemImage: "calendar") {
                                        showingCalendar = true
                                    }
                                    .accessibilityIdentifier("openCalendar")
                                }
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Journal folder", systemImage: "folder") {
                                        showingJournalFolder = true
                                    }
                                    .accessibilityIdentifier("journalFolderInfo")
                                }
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Journal settings", systemImage: "gearshape") {
                                        showingJournalSettings = true
                                    }
                                    .accessibilityIdentifier("openJournalSettings")
                                }
                            }
                    } else {
                        ProgressView("Opening today's entry")
                            .accessibilityIdentifier("openingEntry")
                    }

                case .unavailable(let problem):
                    StorageProblemNotice(
                        problem: problem,
                        useAujoursOwnFolder: wayBackToAujoursOwnFolder
                    ) {
                        await journal.open()
                    }
                    .navigationTitle("Aujour")
                }
            }
            // Outside the states, like the calendar below and for the same
            // reason: choosing a folder closes the journal it was opened from
            // and opens another, and a sheet that lives inside one state is a
            // sheet that vanishes mid-decision.
            // Outside the states for the reason the folder sheet is: every
            // setting on it reopens the journal, and a sheet that lived
            // inside `.open` would close under the finger that changed one.
            .sheet(isPresented: $showingJournalSettings) {
                JournalSettingsSheet(journal: journal)
            }
            .sheet(isPresented: $showingJournalFolder) {
                JournalFolderSheet(journal: journal)
                    // Counted again on the way in: the number from launch is
                    // one edit out of date the moment today's Entry is
                    // created.
                    .task { await journal.recount() }
            }
            // Declared outside the states rather than beside the button that
            // opens it: a destination registered only while one branch of a
            // switch is on screen is one the stack can find itself without.
            //
            // Today's Entry is what the app is for, so the calendar is a step
            // away from it and back — and coming back is what re-reads the
            // folder for a day just filled in.
            .navigationDestination(isPresented: $showingCalendar) {
                if let calendar = journal.calendar {
                    JournalCalendarView(calendar: calendar, journal: journal)
                }
            }
        }
        .task { await journal.open() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive, .background:
                // The last chance to write: there is no next second to save in
                // once the app is out of the way, and the debounce the editor
                // is holding would be spent in it.
                Task { await journal.today?.save() }
            case .active:
                // What coming back to the front means for a journal that is
                // files in a folder — a new day, and a folder that moved on
                // while nothing was listening — is the Journal's to say.
                Task { await journal.cameBackToTheFront() }
            @unknown default:
                break
            }
        }
    }
}

/// Where the journal lives, said the way the user would find it in the Files
/// app — and the way to put it somewhere else.
///
/// Behind a button rather than on the screen: it is the promise the app is
/// built on — these are your files, and here is where they are — and it is
/// also not what anyone opens a journal to read.
///
/// It takes the whole Journal rather than the folder it is currently over,
/// because choosing a folder closes one journal and opens another: the sheet
/// has to still be there, and still be saying something true, while that
/// happens.
private struct JournalFolderSheet: View {
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
                // reachable however long the folder's path runs — a sheet
                // that has pushed its own actions off the bottom is a folder
                // the user cannot change.
                ScrollView {
                    VStack(spacing: 16) {
                        whereTheJournalIs
                        if let problem = journal.folderProblem {
                            FolderProblemNotice(problem: problem, identifier: "folderProblem")
                        }
                        // The other half of "where are my files?": the folder
                        // above, and the shape of the paths inside it.
                        //
                        // On screen whatever state the journal is in, and not
                        // only while it is open — changing the entry path
                        // closes the journal and opens it again, and a
                        // section that came and went with that would take the
                        // migration it is showing with it. What a journal
                        // that is not open cannot do is *change* the path,
                        // which is the button's own business.
                        Divider()
                        EntryPathSection(journal: journal)
                        // And the third part of the same answer: the one line
                        // Aujour writes into a day that is not the user's own
                        // words. On screen in every state for the reason the
                        // entry path is — changing a journal-shaping setting
                        // reopens the journal, and a section that came and went
                        // with that would vanish under the finger that changed
                        // it.
                        Divider()
                        EmbedSyntaxSection(journal: journal)
                    }
                    .frame(maxWidth: .infinity)
                }
                waysToPointItSomewhereElse
            }
            .padding()
            .navigationTitle("Your journal folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Full height rather than half: the sheet answers "where are my
        // files?" in two parts now, and the entry path — a field, what it
        // renders, and the button that changes it — is the part that would be
        // below the fold.
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

extension View {
    /// Says, above a day's Entry, that another version of that day was kept
    /// beside it.
    ///
    /// A modifier because there are two ways into a day and both of them need
    /// it: today's screen, and a day filled in from the calendar. Each shows
    /// only its own day's Parked Files — a notice about March 1st over the
    /// Entry for the 14th would be about a file that is nowhere near it.
    ///
    /// Above the words rather than over them: a version of this day the user
    /// has not seen is news, and the day itself is still theirs to write in
    /// while the notice is up.
    func parkedFilesNotice(from journal: Journal, for day: JournalDay) -> some View {
        safeAreaInset(edge: .top) {
            let parked = journal.parkedFiles(from: day)
            if !parked.isEmpty {
                ParkedFilesNotice(files: parked) {
                    journal.acknowledgeParkedFiles(from: day)
                }
            }
        }
    }
}

/// A day two devices both wrote, said where the user is writing it.
///
/// The Parked File beside the Entry is the lasting notice — it is a file in
/// their vault, which is where they will meet it again. This is so that they
/// meet it at all: without it, the only sign that a version of today was set
/// aside would be a file they have no reason to go looking for.
///
/// Dismissible, and nothing else. Aujour does not offer to merge the two, or
/// to delete either: they are the user's words in the user's folder, and this
/// is the one moment the app is not the right thing to be doing it in
/// (ADR 0002).
struct ParkedFilesNotice: View {
    let files: [ParkedFile]
    let acknowledge: () -> Void

    private var names: String {
        files.map(\.name).formatted(.list(type: .and))
    }

    private var headline: String {
        files.count == 1
            ? "Another version of this day was kept"
            : "\(files.count) other versions of this day were kept"
    }

    private var detail: String {
        files.count == 1
            ? "Two devices wrote it, so Aujour kept both rather than merging them. The other one is beside your entry as \(names) — open it in Files or Obsidian to bring across anything you want."
            : "This day was written on more than one device, so Aujour kept every version rather than merging them. They are beside your entry as \(names) — open them in Files or Obsidian to bring across anything you want."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("parkedFileNotice")
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("parkedFileNames")
            }
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: acknowledge)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("dismissParkedFileNotice")
        }
        .padding(12)
        .background(.thinMaterial)
    }
}

/// Something that went wrong with a folder, in the two sentences it takes to
/// say what and what to do — the compact form, for beside the thing it is
/// about.
private struct FolderProblemNotice: View {
    let problem: StorageProblem

    /// What a test would find it by — the sheet can show two of these at
    /// once, about two different folders.
    let identifier: String

    var body: some View {
        VStack(spacing: 4) {
            Text(problem.message)
                .font(.callout.weight(.semibold))
                .accessibilityIdentifier(identifier)
            Text(problem.suggestion)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}

/// A folder that could not be reached. Says what happened and what to do, and
/// offers the retry — never a blank page that reads as a lost journal.
struct StorageProblemNotice: View {
    let problem: StorageProblem

    /// The way back to the folder Aujour finds for itself, offered only when
    /// the folder that failed is one the user chose.
    ///
    /// Without it, a vault folder renamed on another device is a journal the
    /// user cannot get out of: retrying a folder that is gone will go on
    /// failing, and their words are somewhere Aujour can no longer be pointed.
    var useAujoursOwnFolder: (() async -> Void)? = nil

    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(problem.message, systemImage: "exclamationmark.icloud")
                .accessibilityIdentifier("storageProblem")
        } description: {
            Text(problem.suggestion)
        } actions: {
            Button("Try Again") {
                Task { await retry() }
            }
            .accessibilityIdentifier("retryOpeningJournal")

            if let useAujoursOwnFolder {
                Button("Use Aujour's Own Folder") {
                    Task { await useAujoursOwnFolder() }
                }
                // Not the sheet's button of the same words: a journal that
                // could not be opened can have both on screen at once.
                .accessibilityIdentifier("recoverWithAujoursOwnFolder")
            }
        }
    }
}

// Previews journal into a scratch folder rather than into whatever this Mac's
// iCloud Drive holds, so each one shows the state it is named after.
#Preview("Journaling into iCloud Drive") {
    ContentView(journal: Journal(locator: .preview(.iCloudDrive), settings: .inMemory()))
}

#Preview("Journaling on the device") {
    ContentView(journal: Journal(locator: .preview(.onThisDevice), settings: .inMemory()))
}

#Preview("Journaling into a folder of the user's own") {
    ContentView(journal: Journal(locator: .previewCustomFolder, settings: .inMemory()))
}

#Preview("Nowhere to journal") {
    ContentView(journal: Journal(locator: .preview(nil), settings: .inMemory()))
}

extension JournalRootLocator {
    /// A locator over a scratch folder, pinned to one of Aujour's own
    /// locations — or to none, for the failure the user would see with iCloud
    /// Drive off and the app's own folder unreachable.
    ///
    /// Reachable from the other screens' previews too: any of them that takes
    /// a whole `Journal` needs one that is not this Mac's own.
    static func preview(_ location: JournalRoot.DefaultFolder?) -> JournalRootLocator {
        let folder = URL.temporaryDirectory.appending(path: "AujourPreview/\(location?.rawValue ?? "none")")
        return JournalRootLocator(
            iCloudDocuments: { location == .iCloudDrive ? folder : nil },
            onThisDeviceDocuments: { location == .onThisDevice ? folder : URL(filePath: "/dev/null/nowhere") },
            lastUsedLocation: { nil },
            rememberLocation: { _ in }
        )
    }

    /// A locator already pointed at a folder of the user's own, so the sheet
    /// shows what someone journaling inside an Obsidian vault sees.
    fileprivate static var previewCustomFolder: JournalRootLocator {
        let vault = URL.temporaryDirectory.appending(path: "AujourPreview/Vault/Journal")
        try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        // Straight to a bookmark: a preview has no picker to tap.
        let bookmark = try? vault.bookmarkData()
        return JournalRootLocator(
            iCloudDocuments: { nil },
            onThisDeviceDocuments: { URL(filePath: "/dev/null/nowhere") },
            lastUsedLocation: { nil },
            rememberLocation: { _ in },
            customRoot: CustomJournalRoot(
                storedBookmark: { bookmark },
                rememberBookmark: { _ in }
            )
        )
    }
}
