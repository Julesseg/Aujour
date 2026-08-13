import SwiftUI
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
    @Environment(\.scenePhase) private var scenePhase

    init(journal: Journal = Journal()) {
        _journal = State(wrappedValue: journal)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch journal.state {
                case .opening:
                    ProgressView("Opening your journal")
                        .accessibilityIdentifier("openingJournal")
                        .navigationTitle("Aujour")

                case .open(let root, let fileCount):
                    // There is no open journal without today's Entry over it
                    // — but a blank page is the one thing this screen must
                    // never be, so the unreachable case is the spinner.
                    if let today = journal.today {
                        TodayEntryView(editor: today)
                            .navigationTitle(today.day.spelledOut())
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Journal folder", systemImage: "folder") {
                                        showingJournalFolder = true
                                    }
                                    .accessibilityIdentifier("journalFolderInfo")
                                }
                            }
                            .sheet(isPresented: $showingJournalFolder) {
                                JournalFolderSheet(root: root, fileCount: fileCount)
                                    // Counted again on the way in: the number
                                    // from launch is one edit out of date the
                                    // moment today's Entry is created.
                                    .task { await journal.recount() }
                            }
                    } else {
                        ProgressView("Opening today's entry")
                            .accessibilityIdentifier("openingEntry")
                    }

                case .unavailable(let problem):
                    StorageProblemNotice(problem: problem) {
                        await journal.open()
                    }
                    .navigationTitle("Aujour")
                }
            }
        }
        .task { await journal.open() }
        .onChange(of: scenePhase) { _, phase in
            guard let today = journal.today else { return }
            switch phase {
            case .inactive, .background:
                // The last chance to write: there is no next second to save in
                // once the app is out of the way, and the debounce the editor
                // is holding would be spent in it.
                Task { await today.save() }
            case .active:
                // An app left running overnight comes back to a different day.
                Task { await today.reopenIfTheDayTurned() }
            @unknown default:
                break
            }
        }
    }
}

/// Where the journal lives, said the way the user would find it in the Files
/// app.
///
/// Behind a button rather than on the screen: it is the promise the app is
/// built on — these are your files, and here is where they are — and it is
/// also not what anyone opens a journal to read.
private struct JournalFolderSheet: View {
    let root: JournalRoot
    let fileCount: Int

    @Environment(\.dismiss) private var dismiss

    /// "iPhone" or "iPad" — the app runs on both, and the Files app names the
    /// on-device folder after whichever one this is.
    private var device: String { UIDevice.current.model }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: root.location.symbolName(onDevice: device))
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)

                Text(root.location.name(onDevice: device))
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("journalRootLocation")

                Text(root.location.promise(onDevice: device))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(fileCount == 1 ? "1 file" : "\(fileCount) files")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("journalFileCount")

                Text(root.url.path(percentEncoded: false))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("journalRootPath")
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
        .presentationDetents([.medium])
    }
}

/// A folder that could not be reached. Says what happened and what to do, and
/// offers the retry — never a blank page that reads as a lost journal.
struct StorageProblemNotice: View {
    let problem: StorageProblem
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

#Preview("Nowhere to journal") {
    ContentView(journal: Journal(locator: .preview(nil)))
}

extension JournalRootLocator {
    /// A locator over a scratch folder, pinned to one location — or to none,
    /// for the failure the user would see with iCloud Drive off and the app's
    /// own folder unreachable.
    fileprivate static func preview(_ location: JournalRoot.Location?) -> JournalRootLocator {
        let folder = URL.temporaryDirectory.appending(path: "AujourPreview/\(location?.rawValue ?? "none")")
        return JournalRootLocator(
            iCloudDocuments: { location == .iCloudDrive ? folder : nil },
            onThisDeviceDocuments: { location == .onThisDevice ? folder : URL(filePath: "/dev/null/nowhere") },
            lastUsedLocation: { nil },
            rememberLocation: { _ in }
        )
    }
}
