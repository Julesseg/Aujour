import SwiftUI
import AujourCore

/// The walking skeleton's one screen: where the journal is, and whether Aujour
/// can reach it.
///
/// It is deliberately plain — the today view and the editor land on top of
/// this storage in the next issues. What it has to prove now is the promise
/// the app is built on: a fresh install found a real folder without asking
/// anyone anything, and if it could not, it says so instead of showing an
/// empty page.
struct ContentView: View {
    @State private var journal: Journal

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

                case .open(let root, let fileCount):
                    JournalRootSummary(root: root, fileCount: fileCount)

                case .unavailable(let problem):
                    StorageProblemNotice(problem: problem) {
                        await journal.open()
                    }
                }
            }
            .navigationTitle("Aujour")
        }
        .task { await journal.open() }
    }
}

/// Where the journal lives, said the way the user would find it in the Files
/// app.
private struct JournalRootSummary: View {
    let root: JournalRoot
    let fileCount: Int

    /// "iPhone" or "iPad" — the app runs on both, and the Files app names the
    /// on-device folder after whichever one this is.
    private var device: String { UIDevice.current.model }

    var body: some View {
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
    }
}

/// The folder could not be reached. Says what happened and what to do, and
/// offers the retry — never a blank page that reads as a lost journal.
private struct StorageProblemNotice: View {
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
