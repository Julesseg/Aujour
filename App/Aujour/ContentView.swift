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
    @State private var storage = JournalStorage()

    var body: some View {
        NavigationStack {
            Group {
                switch storage.state {
                case .opening:
                    ProgressView("Opening your journal")
                        .accessibilityIdentifier("openingJournal")

                case .open(let root, let fileCount):
                    JournalRootSummary(root: root, fileCount: fileCount)

                case .unavailable(let problem):
                    StorageProblemNotice(problem: problem) {
                        await storage.open()
                    }
                }
            }
            .navigationTitle("Aujour")
        }
        .task { await storage.open() }
    }
}

/// Where the journal lives, said the way the user would find it in the Files
/// app.
private struct JournalRootSummary: View {
    let root: JournalRoot
    let fileCount: Int

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: root.location == .iCloudDrive ? "icloud" : "iphone")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text(root.location.name)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("journalRootLocation")

            Text(root.location.promise)
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

#Preview("In iCloud Drive") {
    ContentView()
}
