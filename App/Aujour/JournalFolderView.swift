import SwiftUI
import UniformTypeIdentifiers
import AujourCore

/// Where the journal is kept, and the two ways of pointing it somewhere else.
///
/// A page of its own, one step in from the settings sheet. The folder used to
/// open that sheet as a hero — a 44-point glyph, the folder's name, a promise
/// about it, the count, the path, and two buttons pinned to the bottom — which
/// is a screenful of the one setting somebody changes once. Here it is a row
/// showing the folder's name, and everything the hero said is on this page for
/// the day somebody comes looking.
///
/// It is not really a setting, which is why it is the first row rather than
/// part of a group: it is the journal. Each device picks its own once and the
/// bookmark is inherently local (ADR 0003), so nothing about the choice
/// travels.
struct JournalFolderView: View {
    let journal: Journal

    /// Whether the Files picker is up.
    @State private var picking = false

    /// "iPhone" or "iPad" — the Files app names the on-device folder after
    /// whichever one this is.
    private var device: String { UIDevice.current.model }

    var body: some View {
        Form {
            whereItIs
            waysToPointItSomewhereElse
        }
        .settingsPage(titled: "Journal folder")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            // Only a folder that was picked is news: the other outcome is
            // mostly the user tapping Cancel, and an error notice for a mind
            // changed is worse than nothing.
            guard case .success(let folder) = result else { return }
            Task { await journal.use(folder) }
        }
    }

    @ViewBuilder
    private var whereItIs: some View {
        switch journal.state {
        case .opening:
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

        case .open(let root, let entryCount):
            Section {
                LabeledContent("Location", value: root.location.name(onDevice: device))
                    .accessibilityIdentifier("journalRootLocation")

                if let entryCount {
                    LabeledContent(
                        "Entries", value: entryCount == 1 ? "1 entry" : "\(entryCount) entries"
                    )
                    .accessibilityIdentifier("journalEntryCount")
                }

                // A row of its own rather than a value on the right of one: a
                // folder's path is long enough to be the whole row on a phone,
                // and selectable because the reason to read it is to go and
                // find the folder somewhere else.
                Text(root.url.path(percentEncoded: false))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("journalRootPath")
            }

            // Said on the page that can do something about it as well as on
            // the sheet: a folder that cannot be reached is the likeliest
            // reason to be here at all.
            if let problem = journal.folderProblem {
                Section {
                    FolderProblemNotice(problem: problem, identifier: "journalFolderProblem")
                }
            }

        case .unavailable(let problem):
            Section {
                FolderProblemNotice(problem: problem, identifier: "journalRootProblem")
            }
        }
    }

    private var waysToPointItSomewhereElse: some View {
        Section {
            Button("Use a custom folder…") { chooseAFolder() }
                .accessibilityIdentifier("chooseCustomFolder")

            if journal.hasACustomFolder {
                Button("Use Aujour's own folder") {
                    Task { await journal.useAujoursOwnFolder() }
                }
                .accessibilityIdentifier("useAujoursOwnFolder")
            }
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

#Preview {
    NavigationStack {
        JournalFolderView(journal: Journal.inAPreview(over: .system))
    }
}
