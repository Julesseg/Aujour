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
                    JournalCalendarView(calendar: calendar)
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
        .presentationDetents([.medium, .large])
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
    ContentView(journal: Journal(locator: .preview(.iCloudDrive)))
}

#Preview("Journaling on the device") {
    ContentView(journal: Journal(locator: .preview(.onThisDevice)))
}

#Preview("Journaling into a folder of the user's own") {
    ContentView(journal: Journal(locator: .previewCustomFolder))
}

#Preview("Nowhere to journal") {
    ContentView(journal: Journal(locator: .preview(nil)))
}

extension JournalRootLocator {
    /// A locator over a scratch folder, pinned to one of Aujour's own
    /// locations — or to none, for the failure the user would see with iCloud
    /// Drive off and the app's own folder unreachable.
    fileprivate static func preview(_ location: JournalRoot.DefaultFolder?) -> JournalRootLocator {
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
